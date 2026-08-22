import 'dart:async';
import 'package:flutter/material.dart';
import '../models/call_session.dart';
import '../utils/session.dart';
import 'api_service.dart';
import '../screens/call_screen.dart';

class CallService {
  CallService._();

  static final ValueNotifier<CallSessionModel?> activeCallNotifier =
      ValueNotifier<CallSessionModel?>(null);
  static final ValueNotifier<int> callDurationNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<bool> isMutedNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isSpeakerNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isVideoEnabledNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> isFrontCameraNotifier = ValueNotifier<bool>(true);

  static Timer? _callTimer;
  static Timer? _pollingTimer;
  static bool _isPolling = false;

  /// Start background polling for incoming calls if WebSocket is idle
  static void startIncomingCallWatcher(BuildContext context) {
    if (_isPolling) return;
    _isPolling = true;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final myId = await Session.getUserId();
      if (myId == null) return;

      // Don't poll if already in active call
      if (activeCallNotifier.value != null) return;

      final data = await ApiService.getActiveCall(myId);
      if (data != null) {
        final session = CallSessionModel.fromJson(data);
        if (session.status == 'ringing' && session.receiverId == myId) {
          if (activeCallNotifier.value?.id != session.id) {
            activeCallNotifier.value = session;
            // Trigger call screen in incoming mode
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    session: session,
                    partnerId: session.callerId,
                    partnerName: "Partner",
                    isIncoming: true,
                  ),
                ),
              );
            }
          }
        }
      }
    });
  }

  static void stopIncomingCallWatcher() {
    _pollingTimer?.cancel();
    _isPolling = false;
  }

  /// Initiates an outgoing call and opens the CallScreen
  static Future<bool> startCall({
    required BuildContext context,
    required int partnerId,
    required String partnerName,
    required String callType, // "voice" | "video"
  }) async {
    isMutedNotifier.value = false;
    isSpeakerNotifier.value = (callType == "video");
    isVideoEnabledNotifier.value = (callType == "video");
    isFrontCameraNotifier.value = true;
    callDurationNotifier.value = 0;

    final res = await ApiService.initiateCall(partnerId, callType: callType);
    if (res == null) return false;

    final session = CallSessionModel.fromJson(res);
    activeCallNotifier.value = session;

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            session: session,
            partnerId: partnerId,
            partnerName: partnerName,
            isIncoming: false,
          ),
        ),
      );
    }
    return true;
  }

  /// Starts the call duration timer when answered
  static void startDurationTimer() {
    _callTimer?.cancel();
    callDurationNotifier.value = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      callDurationNotifier.value++;
    });
  }

  /// Toggles microphone mute state
  static void toggleMute() {
    isMutedNotifier.value = !isMutedNotifier.value;
  }

  /// Toggles speakerphone state
  static void toggleSpeaker() {
    isSpeakerNotifier.value = !isSpeakerNotifier.value;
  }

  /// Toggles video camera stream on/off
  static void toggleVideo() {
    isVideoEnabledNotifier.value = !isVideoEnabledNotifier.value;
  }

  /// Switches front and back camera
  static void flipCamera() {
    isFrontCameraNotifier.value = !isFrontCameraNotifier.value;
  }

  /// Ends current call and cleans up state
  static Future<void> endCall(int callId) async {
    _callTimer?.cancel();
    _callTimer = null;
    activeCallNotifier.value = null;
    callDurationNotifier.value = 0;
    await ApiService.endCall(callId);
  }
}
