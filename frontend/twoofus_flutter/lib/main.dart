import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/call_notification_service.dart';
import 'services/fcm_client_service.dart';
import 'services/security_service.dart';
import 'services/call_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'utils/session.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Tracks whether Firebase initialization succeeded
bool firebaseInitSucceeded = false;
/// Ensures retry on resume happens at most once
bool hasRetriedFirebaseInit = false;

/// Safely initializes Firebase and FCM client services with try/catch guards
/// so that the app boots normally even if Firebase is unconfigured or throws.
Future<bool> initFirebaseAndFcm({
  Future<void> Function()? firebaseInit,
  Future<void> Function()? fcmInit,
}) async {
  bool coreOk = false;
  try {
    if (firebaseInit != null) {
      await firebaseInit();
    } else {
      await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    }
    coreOk = true;
  } catch (e) {
    if (kDebugMode) debugPrint("[Init] Firebase.initializeApp failed or unconfigured: $e");
  }

  if (coreOk) {
    try {
      if (fcmInit != null) {
        await fcmInit();
      } else {
        await FcmClientService.initialize();
      }
      firebaseInitSucceeded = true;
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint("[Init] FCM setup failed: $e");
    }
  }
  return false;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.init();
  await ApiService.initServerConfig();
  try {
    await CallNotificationService.instance.initialize();
  } catch (e) {
    if (kDebugMode) debugPrint("[Init] CallNotificationService init failed: $e");
  }
  await initFirebaseAndFcm();
  runApp(const TwoOfUsApp());
}

class TwoOfUsApp extends StatefulWidget {
  const TwoOfUsApp({super.key});

  @override
  State<TwoOfUsApp> createState() => _TwoOfUsAppState();
}

class _TwoOfUsAppState extends State<TwoOfUsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeController.updateSystemUiOverlay();
    SecurityService.refreshPasscodeState();
    SecurityService.resetInactivityTimer();
    CallService.startIncomingCallWatcher();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && navigatorKey.currentContext != null) {
        CallNotificationService.instance.checkAndPromptFullScreenIntent(navigatorKey.currentContext!);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SecurityService.cancelInactivityTimer();
    CallService.stopIncomingCallWatcher();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    ThemeController.handlePlatformBrightnessChange();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (navigatorKey.currentContext != null) {
      SecurityService.handleAppLifecycleState(state, navigatorKey.currentContext!);
    }

    // Manage foreground active call notification when app is backgrounded
    if (state == AppLifecycleState.paused) {
      final activeCall = CallService.activeCallNotifier.value;
      if (activeCall != null && activeCall.status == 'ongoing') {
        final isVideo = (activeCall.callType == 'video') && CallService.isVideoEnabledNotifier.value;
        Session.getCachedPartnerName().then((partner) {
          CallNotificationService.instance.showActiveCallNotification(
            partnerName: partner ?? "Partner",
            durationSeconds: CallService.callDurationNotifier.value,
            isVideoActive: isVideo,
          );
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      // Retry once on the next app resume if Firebase init failed on startup
      if (!firebaseInitSucceeded && !hasRetriedFirebaseInit) {
        hasRetriedFirebaseInit = true;
        initFirebaseAndFcm();
      }
      CallNotificationService.instance.cancelActive();
      ThemeController.updateSystemUiOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.currentThemeMode,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<AppTheme>(
          valueListenable: ThemeController.currentTheme,
          builder: (context, activeTheme, _) {
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => SecurityService.resetInactivityTimer(),
              onPointerMove: (_) => SecurityService.resetInactivityTimer(),
              onPointerUp: (_) => SecurityService.resetInactivityTimer(),
              child: MaterialApp(
                navigatorKey: navigatorKey,
                title: 'TwoOfUs',
                debugShowCheckedModeBanner: false,
                theme: ThemeController.buildThemeData(AppTheme.light(activeTheme.accent)),
                darkTheme: ThemeController.buildThemeData(AppTheme.dark(activeTheme.accent)),
                themeMode: themeMode,
                home: const SplashScreen(),
              ),
            );
          },
        );
      },
    );
  }
}