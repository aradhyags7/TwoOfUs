import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_session.dart';
import '../services/api_service.dart';
import '../services/call_notification_service.dart';
import '../services/call_service.dart';
import '../services/call_signaling_client.dart';
import '../services/webrtc_manager.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import '../widgets/encryption_verification_modal.dart';
import '../utils/app_feedback.dart';

class CallScreen extends StatefulWidget {
  final CallSessionModel session;
  final int partnerId;
  final String partnerName;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.session,
    required this.partnerId,
    required this.partnerName,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  Timer? _statusCheckTimer;
  StreamSubscription<Map<String, dynamic>>? _signalingSubscription;

  final WebRTCManager _webrtcManager = WebRTCManager();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  late CallSessionModel _currentSession;
  late bool _isIncoming;
  bool _isConnecting = false;
  String _statusMessage = "";
  bool _isExiting = false;
  Offset _pipOffset = const Offset(20, 120);
  bool _isSwappedVideo = false;

  Color get _bg => ThemeController.currentTheme.value.bg;
  Color get _rose => ThemeController.currentTheme.value.primary;
  Color get _violet => ThemeController.currentTheme.value.secondary;

  @override
  void initState() {
    super.initState();
    _currentSession = widget.session;
    _isIncoming = widget.isIncoming;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initRenderers();
    _setupSignalingListener();

    if (!_isIncoming) {
      _statusMessage = "Calling...";
      if (_currentSession.status == 'ongoing') {
        CallService.startDurationTimer();
      }
    } else {
      _statusMessage = "Incoming ${widget.session.callType} call...";
    }

    _startStatusChecker();
  }

  bool _renderersInitialized = false;

  Future<void> _initRenderers() async {
    if (_renderersInitialized) return;
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      _renderersInitialized = true;
    } catch (e) {
      if (kDebugMode) print("[Error initializing renderers]: $e");
    }
  }

  Future<void> _upgradeToVideo() async {
    final ok = await _webrtcManager.enableVideoInCall();
    if (!ok) {
      if (mounted) {
        AppFeedback.showError(
          context,
          "Camera permission is required to enable video.",
          title: "Permission Required",
        );
      }
      return;
    }

    await _initRenderers();
    if (_webrtcManager.localStream != null) {
      _localRenderer.srcObject = _webrtcManager.localStream;
    }

    setState(() {
      _currentSession = CallSessionModel(
        id: _currentSession.id,
        callerId: _currentSession.callerId,
        receiverId: _currentSession.receiverId,
        callType: 'video',
        status: _currentSession.status,
        createdAt: _currentSession.createdAt,
      );
    });

    CallService.isVideoEnabledNotifier.value = true;
    CallService.isSpeakerNotifier.value = true;
    _webrtcManager.setSpeakerphone(true);

    try {
      final offer = await _webrtcManager.createOffer(isVideo: true);
      CallSignalingClient.instance.sendWebRtcOffer(
        callId: _currentSession.id,
        sdp: offer.sdp ?? '',
        type: offer.type ?? 'offer',
      );
    } catch (e) {
      if (kDebugMode) print("[Upgrade to video error]: $e");
    }
  }

  void _setupSignalingListener() {
    // 1. WebRTC Callbacks
    _webrtcManager.onLocalIceCandidate = (RTCIceCandidate candidate) {
      CallSignalingClient.instance.sendWebRtcIceCandidate(
        callId: _currentSession.id,
        candidatePayload: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    _webrtcManager.onRemoteStreamReady = (MediaStream stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      }
    };

    _webrtcManager.onConnectionStateChanged = (RTCPeerConnectionState state) {
      if (mounted) {
        setState(() {});
      }
    };

    _webrtcManager.onIceConnectionStateChanged = (RTCIceConnectionState state) {
      if (mounted) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
          _statusMessage = "Connecting (NAT Traversal)...";
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _statusMessage = "Connected (DTLS-SRTP P2P)";
          // Ensure hardware audio routing is firmly asserted once ICE is connected
          _webrtcManager.setSpeakerphone(CallService.isSpeakerNotifier.value);
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _statusMessage = "Reconnecting...";
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _statusMessage = "Connection dropped. Retrying...";
        }
        setState(() {});
      }
    };

    _webrtcManager.onIceRestartNeeded = () async {
      if (!_isIncoming && _currentSession.status == 'ongoing' && mounted) {
        try {
          final isVideo = _currentSession.callType == 'video';
          final restartOffer = await _webrtcManager.restartIce(isVideo: isVideo);
          CallSignalingClient.instance.sendWebRtcOffer(
            callId: _currentSession.id,
            sdp: restartOffer.sdp ?? '',
            type: restartOffer.type ?? 'offer',
          );
        } catch (e) {
          if (kDebugMode) print("[ICE Restart error]: $e");
        }
      }
    };

    // 2. Real-time Signaling Dispatcher
    _signalingSubscription = CallSignalingClient.instance.messageStream.listen((msg) async {
      if (_isExiting || !mounted) return;

      final msgCallId = msg['call_id'];
      if (msgCallId != null && msgCallId != _currentSession.id) return;

      final type = msg['type'];
      final isVideo = _currentSession.callType == 'video';

      switch (type) {
        case 'call_ringing':
          if (!_isIncoming && mounted) {
            setState(() {
              _statusMessage = "Ringing...";
            });
          }
          break;

        case 'call_accepted':
          // Partner accepted call
          if (!_isIncoming && mounted) {
            setState(() {
              _statusMessage = "Connecting (Securing E2EE)...";
              _currentSession = CallSessionModel(
                id: _currentSession.id,
                callerId: _currentSession.callerId,
                receiverId: _currentSession.receiverId,
                callType: _currentSession.callType,
                status: 'ongoing',
                createdAt: _currentSession.createdAt,
              );
            });
            CallService.startDurationTimer();

            // Caller initializes WebRTC and sends SDP Offer
            try {
              await _webrtcManager.initialize(isVideo: isVideo);
              await _webrtcManager.setSpeakerphone(CallService.isSpeakerNotifier.value);
              if (isVideo && _webrtcManager.localStream != null) {
                _localRenderer.srcObject = _webrtcManager.localStream;
              }
              final offer = await _webrtcManager.createOffer(isVideo: isVideo);
              CallSignalingClient.instance.sendWebRtcOffer(
                callId: _currentSession.id,
                sdp: offer.sdp ?? '',
                type: offer.type ?? 'offer',
              );
            } catch (e) {
              if (kDebugMode) print("[WebRTC Error creating offer]: $e");
            }
          }
          break;

        case 'webrtc_offer':
          // Receiver receives caller's SDP Offer
          if (_isIncoming || _currentSession.status == 'ongoing') {
            try {
              final payload = msg['payload'] as Map<String, dynamic>;
              final sdp = (payload['sdp'] as String?) ?? '';
              final sdpType = (payload['type'] as String?) ?? 'offer';
              final isOfferVideo = sdp.contains('m=video') || isVideo;

              if (isOfferVideo && _currentSession.callType != 'video') {
                await _initRenderers();
                setState(() {
                  _currentSession = CallSessionModel(
                    id: _currentSession.id,
                    callerId: _currentSession.callerId,
                    receiverId: _currentSession.receiverId,
                    callType: 'video',
                    status: _currentSession.status,
                    createdAt: _currentSession.createdAt,
                  );
                });
                CallService.isVideoEnabledNotifier.value = true;
                CallService.isSpeakerNotifier.value = true;
                _webrtcManager.setSpeakerphone(true);
              }

              if (_webrtcManager.localStream == null) {
                await _webrtcManager.initialize(isVideo: isOfferVideo);
                await _webrtcManager.setSpeakerphone(CallService.isSpeakerNotifier.value);
                if (isOfferVideo && _webrtcManager.localStream != null) {
                  _localRenderer.srcObject = _webrtcManager.localStream;
                }
              }

              final offerDesc = RTCSessionDescription(sdp, sdpType);
              final answer = await _webrtcManager.createAnswer(offerDesc, isVideo: isOfferVideo);

              CallSignalingClient.instance.sendWebRtcAnswer(
                callId: _currentSession.id,
                sdp: answer.sdp ?? '',
                type: answer.type ?? 'answer',
              );

              if (mounted) {
                setState(() {
                  _statusMessage = "Connected (DTLS-SRTP E2EE)";
                });
              }
            } catch (e) {
              if (kDebugMode) print("[WebRTC Error handling offer]: $e");
            }
          }
          break;

        case 'webrtc_answer':
          // Caller receives partner's SDP Answer
          try {
            final payload = msg['payload'] as Map<String, dynamic>;
            final sdp = (payload['sdp'] as String?) ?? '';
            final sdpType = (payload['type'] as String?) ?? 'answer';
            final isAnswerVideo = sdp.contains('m=video');

            if (isAnswerVideo && _currentSession.callType != 'video') {
              await _initRenderers();
              setState(() {
                _currentSession = CallSessionModel(
                  id: _currentSession.id,
                  callerId: _currentSession.callerId,
                  receiverId: _currentSession.receiverId,
                  callType: 'video',
                  status: _currentSession.status,
                  createdAt: _currentSession.createdAt,
                );
              });
              CallService.isVideoEnabledNotifier.value = true;
              CallService.isSpeakerNotifier.value = true;
              _webrtcManager.setSpeakerphone(true);
            }

            final answerDesc = RTCSessionDescription(sdp, sdpType);
            await _webrtcManager.setRemoteAnswer(answerDesc);
            await _webrtcManager.setSpeakerphone(CallService.isSpeakerNotifier.value);

            if (mounted) {
              setState(() {
                _statusMessage = "Connected (DTLS-SRTP P2P)";
              });
            }
          } catch (e) {
            if (kDebugMode) print("[WebRTC Error handling answer]: $e");
          }
          break;

        case 'webrtc_ice_candidate':
          // Either party receives remote ICE Candidate
          try {
            final payload = msg['payload'] as Map<String, dynamic>;
            final candidateStr = payload['candidate'] as String?;
            final sdpMid = payload['sdpMid'] as String?;
            final sdpMLineIndex = payload['sdpMLineIndex'] as int?;

            if (candidateStr != null && candidateStr.isNotEmpty) {
              final candidate = RTCIceCandidate(candidateStr, sdpMid, sdpMLineIndex);
              await _webrtcManager.addRemoteIceCandidate(candidate);
            }
          } catch (e) {
            if (kDebugMode) print("[WebRTC Error adding candidate]: $e");
          }
          break;

        case 'call_rejected':
        case 'call_cancelled':
        case 'call_ended':
        case 'call_busy':
          HapticFeedback.mediumImpact();
          _safeExit();
          break;
      }
    });
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _signalingSubscription?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _webrtcManager.dispose();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    CallService.activeCallNotifier.value = null;
    CallNotificationService.instance.cancelAll();
    super.dispose();
  }

  void _safeExit() {
    if (_isExiting) return;
    _isExiting = true;
    _statusCheckTimer?.cancel();
    _signalingSubscription?.cancel();
    _webrtcManager.dispose();
    CallService.activeCallNotifier.value = null;
    CallNotificationService.instance.cancelAll();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _startStatusChecker() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) async {
      if (_isExiting || !mounted) return;
      // Skip redundant HTTP polling while call is actively ongoing to prevent audio/video lag
      if (_currentSession.status == 'ongoing') return;
      final myId = await Session.getUserId();
      if (myId == null || _isExiting || !mounted) return;

      final updated = await ApiService.getActiveCall(myId);
      if (_isExiting || !mounted) return;

      if (updated == null) {
        // Call was terminated remotely
        HapticFeedback.mediumImpact();
        _safeExit();
        return;
      }

      final newSession = CallSessionModel.fromJson(updated);
      if (newSession.id != _currentSession.id) {
        _safeExit();
        return;
      }

      if (_currentSession.status != newSession.status) {
        setState(() {
          _currentSession = newSession;
        });

        if (newSession.status == 'ongoing') {
          CallService.startDurationTimer();
        } else if (newSession.status == 'ended' ||
            newSession.status == 'rejected' ||
            newSession.status == 'missed') {
          HapticFeedback.mediumImpact();
          _safeExit();
        }
      }
    });
  }

  Future<void> _acceptCall() async {
    HapticFeedback.mediumImpact();
    final isVideo = _currentSession.callType == 'video';

    final hasPerms = await WebRTCManager.requestPermissions(isVideo: isVideo);
    if (!hasPerms) {
      if (mounted) {
        AppFeedback.showError(
          context,
          "Microphone permission is required to answer this call.",
          title: "Permission Required",
        );
      }
      return;
    }

    setState(() => _isConnecting = true);

    // 1. Initialize local media capture
    try {
      await _webrtcManager.initialize(isVideo: isVideo);
      await _webrtcManager.setSpeakerphone(CallService.isSpeakerNotifier.value);
      if (isVideo && _webrtcManager.localStream != null) {
        _localRenderer.srcObject = _webrtcManager.localStream;
      }
    } catch (e) {
      if (kDebugMode) print("[WebRTC Init Exception on Accept]: $e");
    }

    // 2. Send Accept over WebSocket signaling & REST
    CallNotificationService.instance.cancelIncoming();
    CallSignalingClient.instance.sendAccept(callId: _currentSession.id);
    final res = await ApiService.respondToCall(_currentSession.id, 'accept');

    if (!mounted) return;
    setState(() => _isConnecting = false);

    setState(() {
      _isIncoming = false;
      _statusMessage = "Connecting (Securing E2EE)...";
      if (res != null) {
        _currentSession = CallSessionModel.fromJson(res);
      } else {
        _currentSession = CallSessionModel(
          id: _currentSession.id,
          callerId: _currentSession.callerId,
          receiverId: _currentSession.receiverId,
          callType: _currentSession.callType,
          status: 'ongoing',
          createdAt: _currentSession.createdAt,
        );
      }
    });
    CallService.startDurationTimer();
  }

  Future<void> _rejectCall() async {
    if (_isExiting) return;
    HapticFeedback.mediumImpact();
    CallSignalingClient.instance.sendReject(callId: _currentSession.id);
    await ApiService.respondToCall(_currentSession.id, 'reject');
    _safeExit();
  }

  Future<void> _endCall() async {
    if (_isExiting) return;
    HapticFeedback.heavyImpact();
    if (_isIncoming) {
      await _rejectCall();
    } else {
      await CallService.endCall(_currentSession.id);
      _safeExit();
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _currentSession.callType == 'video';
    final isOngoing = _currentSession.status == 'ongoing';

    // Optimize performance: pause pulsing animations when video is actively streaming
    if (isVideo && isOngoing) {
      if (_pulseController.isAnimating) _pulseController.stop();
      if (_waveController.isAnimating) _waveController.stop();
    } else {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
      if (isOngoing && !_waveController.isAnimating) {
        _waveController.repeat(reverse: true);
      }
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _endCall();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: (isVideo && isOngoing)
            ? Stack(
                children: [
                  // Fullscreen video surface with PiP
                  Positioned.fill(child: _buildVideoSurface()),

                  // Video Top Header (Overlay)
                  Positioned(
                    top: 20,
                    left: 20,
                    right: 20,
                    child: SafeArea(
                      child: _buildTopHeader(isOngoing: true),
                    ),
                  ),

                  // Bottom controls (Overlay)
                  Positioned(
                    bottom: 28,
                    left: 20,
                    right: 20,
                    child: SafeArea(
                      child: _buildActiveControls(true),
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  // Background ambient romantic glow
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 1.2,
                          colors: [
                            _violet.withValues(alpha: 0.25),
                            _bg,
                          ],
                        ),
                      ),
                    ),
                  ),

                  SafeArea(
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        _buildTopHeader(isOngoing: isOngoing),
                        Expanded(
                          child: Center(
                            child: _buildVoiceSurface(isOngoing),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          child: _isIncoming
                              ? _buildIncomingControls()
                              : _buildActiveControls(isVideo),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Top Header Widget ────────────────────────────────────────────────────
  Widget _buildTopHeader({required bool isOngoing}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            EncryptionVerificationModal.show(
              context,
              partnerId: widget.partnerId,
              partnerName: widget.partnerName,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: Colors.greenAccent, size: 14),
                SizedBox(width: 6),
                Text(
                  "End-to-End Encrypted (DTLS-SRTP)",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 14),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.partnerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<int>(
          valueListenable: CallService.callDurationNotifier,
          builder: (context, seconds, child) {
            String statusText;
            if (_isIncoming) {
              statusText = "Incoming ${widget.session.callType} call...";
            } else if (_currentSession.status == 'ringing') {
              statusText = _statusMessage.isNotEmpty ? _statusMessage : "Ringing...";
            } else if (_currentSession.status == 'ongoing') {
              statusText = _formatDuration(seconds);
            } else {
              statusText = "Call ${_currentSession.status}";
            }
            return Text(
              statusText,
              style: TextStyle(
                color: isOngoing ? Colors.pinkAccent : Colors.white60,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
        if (isOngoing) ...[
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: CallService.isSpeakerNotifier,
            builder: (context, isSpeaker, _) {
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  CallService.toggleSpeaker();
                  _webrtcManager.setSpeakerphone(CallService.isSpeakerNotifier.value);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isSpeaker ? Colors.greenAccent : Colors.amberAccent).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isSpeaker ? Colors.greenAccent : Colors.amberAccent).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSpeaker ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded,
                        color: isSpeaker ? Colors.greenAccent : Colors.amberAccent,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isSpeaker ? "Speakerphone Active" : "Earpiece Active",
                        style: TextStyle(
                          color: isSpeaker ? Colors.greenAccent : Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // ── Voice Surface with pulsating avatar rings ────────────────────────────
  Widget _buildVoiceSurface(bool isOngoing) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // Outer ripple ring
                Container(
                  width: 190 + (_pulseController.value * 40),
                  height: 190 + (_pulseController.value * 40),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _rose.withValues(alpha: (1.0 - _pulseController.value) * 0.35),
                      width: 2,
                    ),
                  ),
                ),
                // Middle ring
                Container(
                  width: 160 + (_pulseController.value * 24),
                  height: 160 + (_pulseController.value * 24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _violet.withValues(alpha: (1.0 - _pulseController.value) * 0.45),
                      width: 2,
                    ),
                  ),
                ),
                // Avatar container
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [_rose, _violet]),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _rose.withValues(alpha: 0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.partnerName.isNotEmpty ? widget.partnerName[0].toUpperCase() : "P",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 32),

        // Animated Audio Waveform & Status pill
        if (isOngoing) ...[
          AnimatedBuilder(
            animation: _waveController,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(7, (index) {
                  final height = 10.0 +
                      (index % 3 == 0
                          ? _waveController.value * 24
                          : (1 - _waveController.value) * 18);
                  return Container(
                    width: 4,
                    height: height,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.pinkAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: CallService.isMutedNotifier,
            builder: (context, isMuted, child) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isMuted
                      ? Colors.redAccent.withValues(alpha: 0.2)
                      : Colors.greenAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMuted
                        ? Colors.redAccent.withValues(alpha: 0.4)
                        : Colors.greenAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      size: 14,
                      color: isMuted ? Colors.redAccent : Colors.greenAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isMuted ? "Your mic is muted" : "Audio connected",
                      style: TextStyle(
                        color: isMuted ? Colors.redAccent : Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // ── Video Surface with Remote Fullscreen & Floating Local PiP ────────────
  // ── Video Surface with Remote Fullscreen & Floating Draggable PiP ────────
  Widget _buildVideoSurface() {
    final isLocalSwapped = _isSwappedVideo;
    final primaryRenderer = isLocalSwapped ? _localRenderer : _remoteRenderer;
    final pipRenderer = isLocalSwapped ? _remoteRenderer : _localRenderer;
    final isFrontCamera = CallService.isFrontCameraNotifier.value;
    final isLocalVideoOn = CallService.isVideoEnabledNotifier.value;

    return Stack(
      children: [
        // 1. Fullscreen Main Video Stream
        Positioned.fill(
          child: primaryRenderer.srcObject != null &&
                  (!isLocalSwapped || isLocalVideoOn)
              ? RTCVideoView(
                  primaryRenderer,
                  mirror: isLocalSwapped && isFrontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : Container(
                  color: const Color(0xFF10071C),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [_rose, _violet]),
                            boxShadow: [
                              BoxShadow(
                                color: _rose.withValues(alpha: 0.3),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              isLocalSwapped
                                  ? "You"
                                  : (widget.partnerName.isNotEmpty
                                      ? widget.partnerName[0].toUpperCase()
                                      : "P"),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isLocalSwapped
                              ? "Camera is off"
                              : "${widget.partnerName}'s video paused",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),

        // 2. Interactive Draggable Floating Picture-in-Picture (PiP)
        Positioned(
          left: _pipOffset.dx,
          top: _pipOffset.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                final size = MediaQuery.of(context).size;
                final newX = (_pipOffset.dx + details.delta.dx).clamp(12.0, size.width - 132.0);
                final newY = (_pipOffset.dy + details.delta.dy).clamp(70.0, size.height - 260.0);
                _pipOffset = Offset(newX, newY);
              });
            },
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isSwappedVideo = !_isSwappedVideo;
              });
            },
            child: Container(
              width: 120,
              height: 175,
              decoration: BoxDecoration(
                color: const Color(0xFF1E0E30),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: pipRenderer.srcObject != null &&
                            (isLocalSwapped || isLocalVideoOn)
                        ? RTCVideoView(
                            pipRenderer,
                            mirror: !isLocalSwapped && isFrontCamera,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          )
                        : Container(
                            color: Colors.black87,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.videocam_off_rounded,
                                    color: Colors.white.withValues(alpha: 0.6),
                                    size: 28,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isLocalSwapped ? widget.partnerName : "Camera off",
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  // Tap-to-Swap Badge Overlay
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.swap_horiz_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                  // Name Tag
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isLocalSwapped ? widget.partnerName : "You",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Incoming Call Action Buttons (Accept / Reject) ───────────────────────
  Widget _buildIncomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Reject / Decline Button
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _rejectCall,
              borderRadius: BorderRadius.circular(35),
              child: Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF1744),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x66FF1744),
                      blurRadius: 20,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Decline",
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),

        // Accept Button
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _isConnecting ? null : _acceptCall,
              borderRadius: BorderRadius.circular(35),
              child: Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: Color(0xFF00E676),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x6600E676),
                      blurRadius: 20,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: _isConnecting
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      )
                    : const Icon(Icons.call_rounded, color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Accept",
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  // ── Active Ongoing Call Control Bar ──────────────────────────────────────
  Widget _buildActiveControls(bool isVideo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E0E30).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Mute Microphone Button
          ValueListenableBuilder<bool>(
            valueListenable: CallService.isMutedNotifier,
            builder: (context, isMuted, child) {
              return _controlButton(
                icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: isMuted ? "Unmute" : "Mute",
                isActive: isMuted,
                onTap: () {
                  CallService.toggleMute();
                  _webrtcManager.setMicrophoneMute(CallService.isMutedNotifier.value);
                },
              );
            },
          ),

          // Camera On/Off Toggle Button (for video calls)
          if (isVideo)
            ValueListenableBuilder<bool>(
              valueListenable: CallService.isVideoEnabledNotifier,
              builder: (context, isVideoOn, child) {
                return _controlButton(
                  icon: isVideoOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  label: isVideoOn ? "Stop Cam" : "Start Cam",
                  isActive: !isVideoOn,
                  onTap: () {
                    CallService.toggleVideo();
                    _webrtcManager.setVideoEnabled(CallService.isVideoEnabledNotifier.value);
                  },
                );
              },
            ),

          // Flip Camera Button (Front / Back)
          if (isVideo)
            _controlButton(
              icon: Icons.flip_camera_ios_rounded,
              label: "Flip",
              isActive: false,
              onTap: () {
                CallService.flipCamera();
                _webrtcManager.switchCamera();
              },
            ),

          // Upgrade voice call to video button
          if (!isVideo)
            _controlButton(
              icon: Icons.videocam_rounded,
              label: "Video",
              isActive: false,
              onTap: _upgradeToVideo,
            ),

          // Speakerphone Button
          ValueListenableBuilder<bool>(
            valueListenable: CallService.isSpeakerNotifier,
            builder: (context, isSpeaker, child) {
              return _controlButton(
                icon: isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                label: isSpeaker ? "Speaker" : "Earpiece",
                isActive: isSpeaker,
                onTap: () {
                  CallService.toggleSpeaker();
                  _webrtcManager.setSpeakerphone(CallService.isSpeakerNotifier.value);
                },
              );
            },
          ),

          // Hang Up Button
          _controlButton(
            icon: Icons.call_end_rounded,
            label: "End",
            isActive: true,
            isEndCall: true,
            onTap: _endCall,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    bool isEndCall = false,
    required VoidCallback onTap,
  }) {
    Color bg;
    Color iconColor;

    if (isEndCall) {
      bg = const Color(0xFFFF1744);
      iconColor = Colors.white;
    } else if (isActive) {
      bg = Colors.white;
      iconColor = Colors.black87;
    } else {
      bg = Colors.white.withValues(alpha: 0.15);
      iconColor = Colors.white;
    }

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                boxShadow: isEndCall
                    ? [
                        const BoxShadow(
                          color: Color(0x66FF1744),
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isEndCall ? const Color(0xFFFF5252) : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
