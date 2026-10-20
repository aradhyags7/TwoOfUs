import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // Request notification permission via Android plugin
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        await androidPlugin.requestFullScreenIntentPermission();
      }
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] Notification permission check error: $e");
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
        visibility: NotificationVisibility.private,
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
        visibility: NotificationVisibility.private,
      );

      const details = NotificationDetails(android: androidDetails);

      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      // Start the microphone foreground service only after the user accepts and RECORD_AUDIO is granted
      final micGranted = await Permission.microphone.isGranted;
      if (androidPlugin != null && micGranted) {
        await androidPlugin.startForegroundService(
          id: activeNotificationId,
          title: 'Call with $partnerName',
          body: 'Connected • $minutes:$seconds',
          notificationDetails: androidDetails,
          payload: durationSeconds.toString(),
          foregroundServiceTypes: {
            AndroidServiceForegroundType.foregroundServiceTypeMicrophone,
          },
        );
      } else {
        await _notificationsPlugin.show(
          id: activeNotificationId,
          title: 'Call with $partnerName',
          body: 'Connected • $minutes:$seconds',
          notificationDetails: details,
        );
      }
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

  /// Cancels the active call notification and stops the foreground service
  Future<void> cancelActive() async {
    if (!_isInitialized) return;
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.stopForegroundService();
      }
      await _notificationsPlugin.cancel(id: activeNotificationId);
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] cancelActive error: $e");
    }
  }

  /// Cancels all call notifications and stops the foreground service
  Future<void> cancelAll() async {
    if (!_isInitialized) return;
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.stopForegroundService();
      }
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      if (kDebugMode) print("[CallNotificationService] cancelAll error: $e");
    }
  }

  /// Prompts user to check or enable full screen intent permission on Android 14+
  /// if not already granted.
  Future<void> checkAndPromptFullScreenIntent(BuildContext context) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final prefs = await SharedPreferences.getInstance();
    final hasPrompted = prefs.getBool('prompted_full_screen_intent') ?? false;
    if (hasPrompted) return;

    // Check if notification permission is granted
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      final req = await Permission.notification.request();
      if (!req.isGranted) {
        if (context.mounted) {
          _showFullScreenSettingsDialog(context);
        }
        return;
      }
    }

    // Attempt to request full-screen intent permission on Android 14
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestFullScreenIntentPermission();
    }

    if (context.mounted) {
      _showFullScreenSettingsDialog(context);
    }
  }

  void _showFullScreenSettingsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.phone_in_talk_rounded, color: Color(0xFFFF2D75)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Incoming Call Alerts',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: const Text(
            'To show incoming calls when your screen is locked or while using other apps, TwoOfUs needs permission to display full-screen alerts and notifications.\n\nIf calls do not wake your phone, please enable Full Screen Intent & Notifications in App Settings.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                SharedPreferences.getInstance().then((p) => p.setBool('prompted_full_screen_intent', true));
                Navigator.of(ctx).pop();
              },
              child: const Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('prompted_full_screen_intent', true);
                if (ctx.mounted) Navigator.of(ctx).pop();
                await openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF2D75),
                foregroundColor: Colors.white,
              ),
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }
}
