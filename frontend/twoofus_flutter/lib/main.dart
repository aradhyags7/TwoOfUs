import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/call_notification_service.dart';
import 'services/security_service.dart';
import 'services/call_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'utils/session.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.init();
  await ApiService.initServerConfig();
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
        Session.getCachedPartnerName().then((partner) {
          CallNotificationService.instance.showActiveCallNotification(
            partnerName: partner ?? "Partner",
            durationSeconds: CallService.callDurationNotifier.value,
          );
        });
      }
    } else if (state == AppLifecycleState.resumed) {
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