import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/security_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

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
    SecurityService.refreshPasscodeState();
    SecurityService.resetInactivityTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SecurityService.cancelInactivityTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (navigatorKey.currentContext != null) {
      SecurityService.handleAppLifecycleState(state, navigatorKey.currentContext!);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            theme: ThemeController.buildThemeData(activeTheme),
            home: const SplashScreen(),
          ),
        );
      },
    );
  }
}