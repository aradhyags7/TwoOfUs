import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

/// WebRTC peer connection, media capture, and audio routing manager.
class WebRTCManager {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final ValueNotifier<RTCPeerConnectionState> connectionStateNotifier =
      ValueNotifier<RTCPeerConnectionState>(RTCPeerConnectionState.RTCPeerConnectionStateNew);
  final ValueNotifier<RTCIceConnectionState> iceConnectionStateNotifier =
      ValueNotifier<RTCIceConnectionState>(RTCIceConnectionState.RTCIceConnectionStateNew);

  final List<RTCIceCandidate> _pendingIceCandidates = [];
  bool _hasRemoteDescription = false;

  Function(RTCIceCandidate candidate)? onLocalIceCandidate;
  Function(MediaStream remoteStream)? onRemoteStreamReady;
  Function(RTCPeerConnectionState state)? onConnectionStateChanged;
  Function(RTCIceConnectionState state)? onIceConnectionStateChanged;
  Function()? onIceRestartNeeded;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  /// Requests necessary microphone and camera runtime permissions
  static Future<bool> requestPermissions({bool isVideo = false}) async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (kDebugMode) {
        print("[WebRTCManager] Microphone permission not granted: $micStatus");
      }
      return false;
    }

    if (isVideo) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        if (kDebugMode) {
          print("[WebRTCManager] Camera permission not granted: $camStatus");
        }
        return false;
      }
    }

    return true;
  }

  /// Initializes the WebRTC peer connection with STUN and ephemeral TURN servers
  Future<void> initialize({bool isVideo = false}) async {
    await dispose();
    _pendingIceCandidates.clear();
    _hasRemoteDescription = false;

    // 1. Fetch dynamic STUN & TURN credentials from backend
    final turnData = await ApiService.getTurnCredentials();
    final iceServers = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];

    if (turnData != null && turnData['uris'] is List) {
      final uris = List<String>.from(turnData['uris'] as List);
      final username = turnData['username']?.toString() ?? '';
      final password = turnData['password']?.toString() ?? '';

      iceServers.add({
        'urls': uris,
        'username': username,
        'credential': password,
      });
    }

    final configuration = <String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };

    // 2. Create RTCPeerConnection
    _peerConnection = await createPeerConnection(configuration);

    // 3. Register PeerConnection Callbacks
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        onLocalIceCandidate?.call(candidate);
      }
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStreamReady?.call(_remoteStream!);
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      connectionStateNotifier.value = state;
      onConnectionStateChanged?.call(state);
      if (kDebugMode) {
        print("[WebRTCManager] PeerConnection State: $state");
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      iceConnectionStateNotifier.value = state;
      onIceConnectionStateChanged?.call(state);
      if (kDebugMode) {
        print("[WebRTCManager] ICE Connection State: $state");
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        onIceRestartNeeded?.call();
      }
    };

    // 4. Capture local audio (and video if enabled)
    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'highpassFilter': true,
      },
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

    // Add local tracks to peer connection
    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  /// Creates and sets local WebRTC SDP Offer (Caller side)
  Future<RTCSessionDescription> createOffer({bool isVideo = false}) async {
    if (_peerConnection == null) {
      throw Exception("PeerConnection not initialized");
    }

    final offerConstraints = <String, dynamic>{
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isVideo ? 1 : 0,
    };

    final offer = await _peerConnection!.createOffer(offerConstraints);
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  /// Triggers an ICE restart offer during network switches or transient dropouts
  Future<RTCSessionDescription> restartIce({bool isVideo = false}) async {
    if (_peerConnection == null) {
      throw Exception("PeerConnection not initialized");
    }

    final offerConstraints = <String, dynamic>{
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isVideo ? 1 : 0,
      'IceRestart': true,
    };

    final offer = await _peerConnection!.createOffer(offerConstraints);
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  /// Sets remote WebRTC SDP Offer and creates local SDP Answer (Receiver side)
  Future<RTCSessionDescription> createAnswer(
    RTCSessionDescription offer, {
    bool isVideo = false,
  }) async {
    if (_peerConnection == null) {
      throw Exception("PeerConnection not initialized");
    }

    await _peerConnection!.setRemoteDescription(offer);
    _hasRemoteDescription = true;
    _flushPendingIceCandidates();

    final answerConstraints = <String, dynamic>{
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isVideo ? 1 : 0,
    };

    final answer = await _peerConnection!.createAnswer(answerConstraints);
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  /// Sets remote WebRTC SDP Answer (Caller side upon receiving answer from receiver)
  Future<void> setRemoteAnswer(RTCSessionDescription answer) async {
    if (_peerConnection == null) return;
    await _peerConnection!.setRemoteDescription(answer);
    _hasRemoteDescription = true;
    _flushPendingIceCandidates();
  }

  /// Adds a received remote ICE Candidate
  Future<void> addRemoteIceCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) return;

    if (_hasRemoteDescription) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        if (kDebugMode) {
          print("[WebRTCManager] Failed to add candidate: $e");
        }
      }
    } else {
      // Queue candidate until remote description is set
      _pendingIceCandidates.add(candidate);
    }
  }

  void _flushPendingIceCandidates() {
    for (final candidate in _pendingIceCandidates) {
      try {
        _peerConnection?.addCandidate(candidate);
      } catch (e) {
        if (kDebugMode) {
          print("[WebRTCManager] Failed flushing candidate: $e");
        }
      }
    }
    _pendingIceCandidates.clear();
  }

  /// Mutes or unmutes local microphone audio track
  void setMicrophoneMute(bool muted) {
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !muted;
      }
    }
  }

  /// Toggles device speakerphone
  void setSpeakerphone(bool enableSpeaker) {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      _localStream!.getAudioTracks()[0].enableSpeakerphone(enableSpeaker);
    }
  }

  /// Switches front/back camera (video calls)
  Future<void> switchCamera() async {
    if (_localStream != null) {
      for (final track in _localStream!.getVideoTracks()) {
        await Helper.switchCamera(track);
      }
    }
  }

  /// Cleans up and releases all peer connection and media resources
  Future<void> dispose() async {
    _pendingIceCandidates.clear();
    _hasRemoteDescription = false;

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    if (_remoteStream != null) {
      for (final track in _remoteStream!.getTracks()) {
        track.stop();
      }
      await _remoteStream!.dispose();
      _remoteStream = null;
    }

    if (_peerConnection != null) {
      await _peerConnection!.close();
      await _peerConnection!.dispose();
      _peerConnection = null;
    }

    connectionStateNotifier.value = RTCPeerConnectionState.RTCPeerConnectionStateClosed;
    iceConnectionStateNotifier.value = RTCIceConnectionState.RTCIceConnectionStateClosed;
  }
}
