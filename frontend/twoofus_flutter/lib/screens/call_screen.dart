import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_session.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';
import '../services/call_signaling_client.dart';
import '../services/webrtc_manager.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';

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

  Future<void> _initRenderers() async {
    final isVideo = _currentSession.callType == 'video';
    if (isVideo) {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
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

              if (_webrtcManager.localStream == null) {
                await _webrtcManager.initialize(isVideo: isVideo);
                if (isVideo && _webrtcManager.localStream != null) {
                  _localRenderer.srcObject = _webrtcManager.localStream;
                }
              }

              final offerDesc = RTCSessionDescription(sdp, sdpType);
              final answer = await _webrtcManager.createAnswer(offerDesc, isVideo: isVideo);

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
            final answerDesc = RTCSessionDescription(sdp, sdpType);
            await _webrtcManager.setRemoteAnswer(answerDesc);

            if (mounted) {
              setState(() {
                _statusMessage = "Connected (DTLS-SRTP E2EE)";
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
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    CallService.activeCallNotifier.value = null;
    super.dispose();
  }

  void _safeExit() {
    if (_isExiting) return;
    _isExiting = true;
    _statusCheckTimer?.cancel();
    _signalingSubscription?.cancel();
    _webrtcManager.dispose();
    CallService.activeCallNotifier.value = null;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _startStatusChecker() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) async {
      if (_isExiting || !mounted) return;
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
    setState(() => _isConnecting = true);

    final isVideo = _currentSession.callType == 'video';

    // 1. Initialize local media capture
    try {
      await _webrtcManager.initialize(isVideo: isVideo);
      if (isVideo && _webrtcManager.localStream != null) {
        _localRenderer.srcObject = _webrtcManager.localStream;
      }
    } catch (e) {
      if (kDebugMode) print("[WebRTC Init Exception on Accept]: $e");
    }

    // 2. Send Accept over WebSocket signaling & REST
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

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _endCall();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // Background ambient romantic glow
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      _violet.withValues(alpha: 0.2),
                      _bg,
                    ],
                  ),
                ),
              ),
            ),

            if (isVideo && isOngoing)
              _buildVideoSurface()
            else
              _buildVoiceSurface(),

            // Top Header: Partner info & E2EE badge
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: SafeArea(
                child: Column(
                  children: [
                    Container(
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
                        ],
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
                  ],
                ),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: SafeArea(
                child: _isIncoming ? _buildIncomingControls() : _buildActiveControls(isVideo),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Voice Surface with pulsating avatar rings ────────────────────────────
  Widget _buildVoiceSurface() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ripple ring
                  Container(
                    width: 200 + (_pulseController.value * 50),
                    height: 200 + (_pulseController.value * 50),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _rose.withValues(alpha: (1.0 - _pulseController.value) * 0.4),
                        width: 2,
                      ),
                    ),
                  ),
                  // Middle ring
                  Container(
                    width: 170 + (_pulseController.value * 30),
                    height: 170 + (_pulseController.value * 30),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _violet.withValues(alpha: (1.0 - _pulseController.value) * 0.5),
                        width: 2,
                      ),
                    ),
                  ),
                  // Avatar container
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_rose, _violet]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _rose.withValues(alpha: 0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        widget.partnerName.isNotEmpty ? widget.partnerName[0].toUpperCase() : "P",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 48),

          // Animated Audio Waveform (when ongoing)
          if (_currentSession.status == 'ongoing')
            AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(7, (index) {
                    final height = 12.0 +
                        (index % 3 == 0
                            ? _waveController.value * 28
                            : (1 - _waveController.value) * 22);
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
        ],
      ),
    );
  }

  // ── Video Surface with Remote Fullscreen & Floating Local PiP ────────────
  Widget _buildVideoSurface() {
    return Stack(
      children: [
        // Fullscreen Remote Video Stream
        Positioned.fill(
          child: _remoteRenderer.srcObject != null
              ? RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : Container(
                  color: const Color(0xFF12081E),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_rounded, color: _rose.withValues(alpha: 0.4), size: 72),
                        const SizedBox(height: 12),
                        Text(
                          "Connecting to ${widget.partnerName}...",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),

        // Floating Local Picture-in-Picture (PiP)
        Positioned(
          top: 140,
          right: 20,
          child: ValueListenableBuilder<bool>(
            valueListenable: CallService.isVideoEnabledNotifier,
            builder: (context, isVideoOn, child) {
              return Container(
                width: 110,
                height: 160,
                decoration: BoxDecoration(
                  color: const Color(0xFF221133),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: isVideoOn && _localRenderer.srcObject != null
                      ? RTCVideoView(
                          _localRenderer,
                          mirror: CallService.isFrontCameraNotifier.value,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : Container(
                          color: Colors.black87,
                          child: const Center(
                            child: Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 30),
                          ),
                        ),
                ),
              );
            },
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E0E30).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Mute Button
          ValueListenableBuilder<bool>(
            valueListenable: CallService.isMutedNotifier,
            builder: (context, isMuted, child) {
              return _controlButton(
                icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                isActive: isMuted,
                onTap: () {
                  CallService.toggleMute();
                  _webrtcManager.setMicrophoneMute(CallService.isMutedNotifier.value);
                },
              );
            },
          ),

          // Speaker Button
          ValueListenableBuilder<bool>(
            valueListenable: CallService.isSpeakerNotifier,
            builder: (context, isSpeaker, child) {
              return _controlButton(
                icon: isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                isActive: isSpeaker,
                onTap: () {
                  CallService.toggleSpeaker();
                  _webrtcManager.setSpeakerphone(CallService.isSpeakerNotifier.value);
                },
              );
            },
          ),

          // Flip Camera (for video calls)
          if (isVideo)
            _controlButton(
              icon: Icons.flip_camera_ios_rounded,
              isActive: false,
              onTap: () {
                CallService.flipCamera();
                _webrtcManager.switchCamera();
              },
            ),

          // Hang Up Button
          _controlButton(
            icon: Icons.call_end_rounded,
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
      child: Container(
        width: 52,
        height: 52,
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
    );
  }
}
