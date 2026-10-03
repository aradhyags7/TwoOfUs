import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service managing native Android heads-up incoming call alerts,
/// full-screen intents, and active call foreground notifications.
class CallNotificationService {
  CallNotificationService._();
  static final CallNotificationService instance = CallNotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  static const String _incomingChannelId = 'twoofus_incoming_calls';
  static const String _incomingChannelName = 'Incoming Calls';

  static const String _activeChannelId = 'twoofus_active_call';
  static const String _activeChannelName = 'Active Call';

  static const int incomingNotificationId = 7701;
  static const int activeNotificationId = 7702;

  Function(String action, int callId)? onNotificationAction;

  /// Initializes notification channels and platform handlers
  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(
      android: androidSettings,
    );

    try {
      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final actionId = response.actionId;
          final payload = response.payload;
          if (kDebugMode) {
            print("[CallNotificationService] Action tapped: $actionId, payload: $payload");
          }

          if (payload != null) {
            final callId = int.tryParse(payload) ?? 0;
            if (actionId != null && actionId.isNotEmpty) {
              onNotificationAction?.call(actionId, callId);
            } else {
              // Default tap on notification body -> treat as accept/open
              onNotificationAction?.call('accept', callId);
            }
          }
        },
      );
      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] Plugin initialize error: $e");
      return;
    }

    // Request Android 13+ POST_NOTIFICATIONS permission
    try {
      await Permission.notification.request();
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] Notification permission request error: $e");
    }
  }

  /// Displays high-priority heads-up incoming call alert with full-screen intent
  Future<void> showIncomingCallNotification({
    required int callId,
    required String callerName,
    required String callType,
  }) async {
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return;
    }

    try {
      final vibrationPattern = Int64List.fromList([0, 800, 400, 800, 400, 800]);

      final androidDetails = AndroidNotificationDetails(
        _incomingChannelId,
        _incomingChannelName,
        channelDescription: 'High-priority full-screen incoming call notifications',
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        ongoing: true,
        autoCancel: false,
        vibrationPattern: vibrationPattern,
        enableVibration: true,
        playSound: true,
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'decline',
            'Decline',
            cancelNotification: true,
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            'accept',
            'Accept',
            cancelNotification: true,
            showsUserInterface: true,
          ),
        ],
      );

      final details = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        id: incomingNotificationId,
        title: 'Incoming ${callType.toUpperCase()} Call',
        body: '$callerName is calling you...',
        notificationDetails: details,
        payload: callId.toString(),
      );
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] showIncomingCallNotification error: $e");
    }
  }

  /// Displays an ongoing low-priority notification while call is actively connected
  Future<void> showActiveCallNotification({
    required String partnerName,
    required int durationSeconds,
  }) async {
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return;
    }

    try {
      final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
      final seconds = (durationSeconds % 60).toString().padLeft(2, '0');

      const androidDetails = AndroidNotificationDetails(
        _activeChannelId,
        _activeChannelName,
        channelDescription: 'Active ongoing call foreground notification',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        playSound: false,
        enableVibration: false,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
      );

      const details = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        id: activeNotificationId,
        title: 'Call with $partnerName',
        body: 'Connected • $minutes:$seconds',
        notificationDetails: details,
      );
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] showActiveCallNotification error: $e");
    }
  }

  /// Cancels the incoming call notification
  Future<void> cancelIncoming() async {
    if (!_isInitialized) return;
    try {
      await _notificationsPlugin.cancel(id: incomingNotificationId);
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] cancelIncoming error: $e");
    }
  }

  /// Cancels the active call notification
  Future<void> cancelActive() async {
    if (!_isInitialized) return;
    try {
      await _notificationsPlugin.cancel(id: activeNotificationId);
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] cancelActive error: $e");
    }
  }

  /// Cancels all call notifications
  Future<void> cancelAll() async {
    if (!_isInitialized) return;
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] cancelAll error: $e");
    }
  }
}
