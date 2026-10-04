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

    // 0. Configure native platform audio session for voice/video communication
    if (WebRTC.platformIsAndroid) {
      try {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration(
            manageAudioFocus: true,
            androidAudioMode: AndroidAudioMode.inCommunication,
            androidAudioFocusMode: AndroidAudioFocusMode.gain,
            androidAudioStreamType: AndroidAudioStreamType.voiceCall,
            androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.voiceCommunication,
            androidAudioAttributesContentType: AndroidAudioAttributesContentType.speech,
          ),
        );
      } catch (e) {
        if (kDebugMode) print("[WebRTCManager] Failed setting Android audio configuration: $e");
      }
    } else if (WebRTC.platformIsIOS) {
      try {
        await Helper.setAppleAudioConfiguration(
          AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playAndRecord,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.defaultToSpeaker,
              AppleAudioCategoryOption.allowBluetooth,
              AppleAudioCategoryOption.allowBluetoothA2DP,
            },
            appleAudioMode: AppleAudioMode.voiceChat,
          ),
        );
        await Helper.ensureAudioSession();
      } catch (e) {
        if (kDebugMode) print("[WebRTCManager] Failed setting Apple audio configuration: $e");
      }
    }

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

    _peerConnection!.onTrack = (RTCTrackEvent event) async {
      if (kDebugMode) {
        print("[WebRTCManager] onTrack: kind=${event.track.kind}, id=${event.track.id}, streams=${event.streams.length}");
      }

      // Explicitly enable remote audio track, boost hardware playback volume, and verify routing
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
        try {
          await Helper.setVolume(1.0, event.track);
        } catch (e) {
          if (kDebugMode) {
            print("[WebRTCManager] Helper.setVolume error: $e");
          }
        }
        await setSpeakerphone(_isSpeakerphoneOn);
      }

      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
      } else if (_remoteStream == null) {
        try {
          _remoteStream = await createLocalMediaStream('remote_stream_${DateTime.now().millisecondsSinceEpoch}');
        } catch (e) {
          if (kDebugMode) {
            print("[WebRTCManager] Fallback createLocalMediaStream error: $e");
          }
        }
      }

      if (_remoteStream != null) {
        if (!_remoteStream!.getTracks().any((t) => t.id == event.track.id)) {
          _remoteStream!.addTrack(event.track);
        }
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

    // 4. Capture local audio (and video if enabled) with optimized mobile constraints
    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'googEchoCancellation': true,
        'googAutoGainControl': true,
        'googNoiseSuppression': true,
        'googHighpassFilter': true,
      },
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640, 'max': 960},
              'height': {'ideal': 480, 'max': 720},
              'frameRate': {'ideal': 24, 'max': 30},
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      if (kDebugMode) {
        print("[WebRTCManager] getUserMedia with constraints failed: $e. Retrying with basic constraints...");
      }
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });
    }

    // Ensure all local audio tracks are explicitly enabled for transmission
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = true;
    }

    // Add local tracks to peer connection
    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    // Ensure Unified Plan transceivers are explicitly set to SendRecv
    try {
      final transceivers = await _peerConnection!.getTransceivers();
      for (final t in transceivers) {
        if (t.sender.track?.kind == 'audio') {
          await t.setDirection(TransceiverDirection.SendRecv);
        } else if (t.sender.track?.kind == 'video') {
          await t.setDirection(isVideo ? TransceiverDirection.SendRecv : TransceiverDirection.RecvOnly);
        }
      }
    } catch (e) {
      if (kDebugMode) print("[WebRTCManager] Error setting transceiver directions: $e");
    }

    // Ensure audio routing is active on the device loudspeaker by default
    _isSpeakerphoneOn = true;
    await setSpeakerphone(_isSpeakerphoneOn);
  }

  bool _isSpeakerphoneOn = true;
  bool get isSpeakerphoneOn => _isSpeakerphoneOn;

  /// Optimizes SDP for mobile networks with Opus Forward Error Correction and DTX
  String _optimizeSdp(String sdp, {bool isVideo = false}) {
    if (!sdp.contains('opus/48000')) return sdp;

    final lines = sdp.split(RegExp(r'\r\n|\n'));
    String? opusPt;
    for (final line in lines) {
      final match = RegExp(r'^a=rtpmap:(\d+)\s+opus/48000/2').firstMatch(line.trim());
      if (match != null) {
        opusPt = match.group(1);
        break;
      }
    }

    if (opusPt == null) return sdp;

    bool fmtpFound = false;
    final updatedLines = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('a=fmtp:$opusPt')) {
        fmtpFound = true;
        var fmtp = trimmed;
        if (!fmtp.contains('useinbandfec=')) {
          fmtp += ';useinbandfec=1';
        }
        if (!fmtp.contains('usedtx=')) {
          fmtp += ';usedtx=1';
        }
        updatedLines.add(fmtp);
      } else {
        updatedLines.add(trimmed);
      }
    }

    if (!fmtpFound) {
      final result = <String>[];
      for (final line in updatedLines) {
        result.add(line);
        if (line.startsWith('a=rtpmap:$opusPt opus/48000/2')) {
          result.add('a=fmtp:$opusPt useinbandfec=1;usedtx=1');
        }
      }
      return '${result.join('\r\n')}\r\n';
    }

    return '${updatedLines.join('\r\n')}\r\n';
  }

  /// Creates and sets local WebRTC SDP Offer (Caller side)
  Future<RTCSessionDescription> createOffer({bool isVideo = false}) async {
    if (_peerConnection == null) {
      throw Exception("PeerConnection not initialized");
    }

    // In Unified Plan, transceivers are configured via addTrack & setDirection; avoid legacy offerToReceiveAudio duplicate m-lines
    final offer = await _peerConnection!.createOffer({});
    final optimizedSdp = _optimizeSdp(offer.sdp ?? '', isVideo: isVideo);
    final optimizedOffer = RTCSessionDescription(optimizedSdp, offer.type);
    await _peerConnection!.setLocalDescription(optimizedOffer);
    return optimizedOffer;
  }

  /// Triggers an ICE restart offer during network switches or transient dropouts
  Future<RTCSessionDescription> restartIce({bool isVideo = false}) async {
    if (_peerConnection == null) {
      throw Exception("PeerConnection not initialized");
    }

    final offer = await _peerConnection!.createOffer({'iceRestart': true});
    final optimizedSdp = _optimizeSdp(offer.sdp ?? '', isVideo: isVideo);
    final optimizedOffer = RTCSessionDescription(optimizedSdp, offer.type);
    await _peerConnection!.setLocalDescription(optimizedOffer);
    return optimizedOffer;
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

    // In Unified Plan, answer automatically reflects negotiated media transceivers
    final answer = await _peerConnection!.createAnswer({});
    final optimizedSdp = _optimizeSdp(answer.sdp ?? '', isVideo: isVideo);
    final optimizedAnswer = RTCSessionDescription(optimizedSdp, answer.type);
    await _peerConnection!.setLocalDescription(optimizedAnswer);
    return optimizedAnswer;
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
  Future<void> setMicrophoneMute(bool muted) async {
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !muted;
      }
    }
    try {
      await Helper.setMicrophoneMuted(muted);
    } catch (_) {}
  }

  /// Sets device speakerphone on or off using the official platform Helper API with Bluetooth routing preference
  Future<void> setSpeakerphone(bool enableSpeaker) async {
    _isSpeakerphoneOn = enableSpeaker;
    try {
      await Helper.ensureAudioSession();
      if (enableSpeaker) {
        try {
          await Helper.setSpeakerphoneOnButPreferBluetooth();
        } catch (_) {
          await Helper.setSpeakerphoneOn(true);
        }
      } else {
        await Helper.setSpeakerphoneOn(false);
      }
      if (kDebugMode) {
        print("[WebRTCManager] Speakerphone successfully routed: $enableSpeaker (with Bluetooth preference)");
      }
    } catch (e) {
      if (kDebugMode) {
        print("[WebRTCManager] Failed to set speakerphone: $e");
      }
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

  /// Enables or disables local video track (camera mute/unmute)
  void setVideoEnabled(bool enabled) {
    if (_localStream != null) {
      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = enabled;
      }
    }
  }

  /// Dynamically upgrades an active audio-only call to video
  Future<bool> enableVideoInCall() async {
    final hasCam = await Permission.camera.request();
    if (!hasCam.isGranted) return false;

    try {
      final videoStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 640, 'max': 960},
          'height': {'ideal': 480, 'max': 720},
          'frameRate': {'ideal': 24, 'max': 30},
        },
      });

      if (videoStream.getVideoTracks().isEmpty) return false;
      final videoTrack = videoStream.getVideoTracks().first;

      if (_localStream != null) {
        _localStream!.addTrack(videoTrack);
      } else {
        _localStream = videoStream;
      }

      if (_peerConnection != null) {
        await _peerConnection!.addTrack(videoTrack, _localStream!);
      }

      // Ensure speakerphone is enabled for video mode
      await setSpeakerphone(true);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print("[WebRTCManager] Failed to upgrade to video: $e");
      }
      return false;
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
