import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'call_notification_service.dart';
import 'call_service.dart';

/// Top-level background message handler invoked by Firebase Messaging when app
/// is backgrounded or killed/terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure notification channels and native platform plugins are initialized inside background isolate
  await CallNotificationService.instance.initialize();

  final data = message.data;
  if (data['type'] == 'incoming_call') {
    final callId = int.tryParse(data['call_id']?.toString() ?? '') ?? 0;
    if (callId > 0) {
      if (CallService.isCallAlreadyHandled(callId)) {
        if (kDebugMode) {
          print("[FCM Background] Duplicate incoming_call push ignored for call_id=$callId");
        }
        return;
      }
      CallService.markCallHandled(callId);

      final callerName = data['caller_name']?.toString() ?? 'Partner';
      final callType = data['call_type']?.toString() ?? 'voice';
      await CallNotificationService.instance.showIncomingCallNotification(
        callId: callId,
        callerName: callerName,
        callType: callType,
      );
    }
  }
}

/// Service managing client-side FCM initialization, background message routing,
/// token registration, and token refreshes via /call/device-token.
class FcmClientService {
  static bool _isInitialized = false;

  /// Initializes Firebase and configures foreground & background message listeners.
  /// If Firebase configuration (google-services.json) is missing or uninitialized,
  /// logs gracefully without crashing.
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp().timeout(const Duration(milliseconds: 500));
    } catch (e) {
      if (kDebugMode) {
        print("[FCM] Firebase.initializeApp note: $e");
      }
      return;
    }

    try {
      // Register top-level background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Handle foreground FCM data messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final data = message.data;
        if (data['type'] == 'incoming_call') {
          final callId = int.tryParse(data['call_id']?.toString() ?? '') ?? 0;
          if (callId > 0) {
            if (CallService.isCallAlreadyHandled(callId)) {
              if (kDebugMode) {
                print("[FCM Foreground] Duplicate incoming_call push ignored for call_id=$callId");
              }
              return;
            }
            CallService.markCallHandled(callId);

            final callerName = data['caller_name']?.toString() ?? 'Partner';
            final callType = data['call_type']?.toString() ?? 'voice';
            CallNotificationService.instance.showIncomingCallNotification(
              callId: callId,
              callerName: callerName,
              callType: callType,
            );
          }
        }
      });

      // Listen for push registration token events (firebase_messaging 17.0.0+)
      FirebaseMessaging.instance.onRegistered.listen((newToken) {
        if (newToken.isNotEmpty) {
          _registerToken(newToken);
        }
      });

      try {
        await FirebaseMessaging.instance.register();
      } catch (e) {
        if (kDebugMode) print("[FCM] register() note: $e");
      }

      // TODO(firebase_messaging: 17.0.0): getToken/onTokenRefresh are deprecated in favor of register() and onRegistered stream.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }

      _isInitialized = true;
      if (kDebugMode) {
        print("[FCM] FcmClientService initialized successfully");
      }
    } catch (e) {
      if (kDebugMode) {
        print("[FCM] FcmClientService setup error: $e");
      }
    }
  }

  /// Sends device push token to backend via /call/device-token
  static Future<void> _registerToken(String pushToken) async {
    final platform = (!kIsWeb && Platform.isIOS) ? 'ios' : 'android';
    final success = await ApiService.registerDevicePushToken(pushToken, platform: platform);
    if (kDebugMode) {
      print("[FCM] Registered device push token with backend ($platform): $success");
    }
  }

  /// Called after successful login or session recovery to ensure token is synced
  static Future<void> syncTokenIfLoggedIn() async {
    try {
      // TODO(firebase_messaging: 17.0.0): getToken/onTokenRefresh are deprecated in favor of register() and onRegistered stream.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }
    } catch (_) {}
  }
}
