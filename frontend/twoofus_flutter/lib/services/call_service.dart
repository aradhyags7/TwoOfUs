import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/call_session.dart';
import '../utils/session.dart';
import 'api_service.dart';
import 'call_notification_service.dart';
import 'call_signaling_client.dart';
import 'webrtc_manager.dart';
import '../screens/call_screen.dart';
import '../main.dart';
import '../utils/app_feedback.dart';

class CallService {
  CallService._();

  static final ValueNotifier<CallSessionModel?> activeCallNotifier =
      ValueNotifier<CallSessionModel?>(null);
  static final ValueNotifier<int> callDurationNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<bool> isMutedNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isSpeakerNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> isVideoEnabledNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> isFrontCameraNotifier = ValueNotifier<bool>(true);

  static Timer? _callTimer;
  static Timer? _pollingTimer;
  static StreamSubscription<Map<String, dynamic>>? _signalingSub;
  static bool _isWatching = false;

  /// Starts real-time WebSocket signaling listener and background fallback polling
  static void startIncomingCallWatcher([BuildContext? context]) {
    if (_isWatching) return;
    _isWatching = true;

    // 1. Initialize native notification channels and response actions
    CallNotificationService.instance.initialize();
    CallNotificationService.instance.onNotificationAction = (action, callId) async {
      if (action == 'decline') {
        CallSignalingClient.instance.sendReject(callId: callId, reason: 'declined');
        CallNotificationService.instance.cancelIncoming();
        activeCallNotifier.value = null;
      } else if (action == 'accept') {
        CallNotificationService.instance.cancelIncoming();
        final session = activeCallNotifier.value;
        if (session != null && navigatorKey.currentState != null) {
          String partnerName = await Session.getCachedPartnerName() ?? "Partner";
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => CallScreen(
                session: session,
                partnerId: session.callerId,
                partnerName: partnerName,
                isIncoming: true,
              ),
            ),
          );
        }
      }
    };

    // 2. Connect WebSocket signaling channel
    CallSignalingClient.instance.connect();

    // 3. Listen to real-time WebSockets signaling events
    _signalingSub?.cancel();
    _signalingSub = CallSignalingClient.instance.messageStream.listen((msg) async {
      final type = msg['type'];
      if (type == 'incoming_call') {
        final myId = await Session.getUserId();
        if (myId == null) return;

        final callId = msg['call_id'] as int;
        final callerId = msg['caller_id'] as int;
        final callerName = (msg['caller_name'] as String?) ?? 'Partner';

        // If user is already on a call, reject as busy
        if (activeCallNotifier.value != null) {
          CallSignalingClient.instance.sendReject(callId: callId, reason: 'busy');
          return;
        }

        final session = CallSessionModel.fromSignaling(msg, myId);
        activeCallNotifier.value = session;

        // Show native heads-up notification with Full-Screen Intent
        CallNotificationService.instance.showIncomingCallNotification(
          callId: callId,
          callerName: callerName,
          callType: session.callType,
        );

        // Ringing feedback
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 250), () => HapticFeedback.heavyImpact());

        // Acknowledge ringing to caller
        CallSignalingClient.instance.sendRinging(callId: callId, targetId: callerId);

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              session: session,
              partnerId: callerId,
              partnerName: callerName,
              isIncoming: true,
            ),
          ),
        );
      } else if (type == 'call_cancelled' ||
          type == 'call_ended' ||
          type == 'call_rejected' ||
          type == 'call_busy') {
        CallNotificationService.instance.cancelIncoming();
      }
    });

    // 4. Low-frequency polling fallback in case WebSocket reconnects on flaky networks
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      final myId = await Session.getUserId();
      if (myId == null) {
        stopIncomingCallWatcher();
        return;
      }

      if (activeCallNotifier.value != null) return;

      final data = await ApiService.getActiveCall(myId);
      if (data != null) {
        final session = CallSessionModel.fromJson(data);
        if (session.status == 'ringing' && session.receiverId == myId) {
          if (activeCallNotifier.value?.id != session.id) {
            activeCallNotifier.value = session;

            HapticFeedback.heavyImpact();
            Future.delayed(const Duration(milliseconds: 250), () => HapticFeedback.heavyImpact());

            String partnerName = await Session.getCachedPartnerName() ?? "Partner";
            if (partnerName == "Partner" || partnerName.isEmpty) {
              try {
                final prof = await ApiService.getProfile(session.callerId);
                if (prof != null && prof["username"] != null) {
                  partnerName = prof["username"].toString();
                }
              } catch (_) {}
            }

            // Show native heads-up notification with Full-Screen Intent
            CallNotificationService.instance.showIncomingCallNotification(
              callId: session.id,
              callerName: partnerName,
              callType: session.callType,
            );

            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => CallScreen(
                  session: session,
                  partnerId: session.callerId,
                  partnerName: partnerName,
                  isIncoming: true,
                ),
              ),
            );
          }
        }
      }
    });
  }

  static void stopIncomingCallWatcher() {
    _signalingSub?.cancel();
    _signalingSub = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isWatching = false;
    CallNotificationService.instance.cancelAll();
    CallSignalingClient.instance.disconnect();
  }

  /// Initiates an outgoing call and opens the CallScreen
  static Future<bool> startCall({
    required BuildContext context,
    required int partnerId,
    required String partnerName,
    required String callType, // "voice" | "video"
  }) async {
    // 1. Verify runtime microphone/camera permissions
    final hasPermissions = await WebRTCManager.requestPermissions(
      isVideo: callType == "video",
    );
    if (!hasPermissions) {
      if (context.mounted) {
        AppFeedback.showError(
          context,
          "Microphone and camera permissions are required to place calls.",
          title: "Permission Required",
        );
      }
      return false;
    }

    isMutedNotifier.value = false;
    isSpeakerNotifier.value = true;
    isVideoEnabledNotifier.value = (callType == "video");
    isFrontCameraNotifier.value = true;
    callDurationNotifier.value = 0;

    // 2. Send invitation over WebSocket signaling
    CallSignalingClient.instance.sendInvite(
      targetId: partnerId,
      callType: callType,
    );

    // 3. Initiate call session in database
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
  static Future<void> endCall(int callId, [String reason = 'normal_hangup']) async {
    _callTimer?.cancel();
    _callTimer = null;
    activeCallNotifier.value = null;
    callDurationNotifier.value = 0;

    // Cancel all notifications
    CallNotificationService.instance.cancelAll();

    // Send real-time termination signal
    CallSignalingClient.instance.sendEnd(callId: callId, reason: reason);

    // Persist session end in DB
    await ApiService.endCall(callId);
  }
}
