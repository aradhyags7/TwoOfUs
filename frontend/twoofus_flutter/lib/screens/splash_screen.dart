import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/security_service.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'passcode_setup_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — SplashScreen
// Design mirrors the rest of the app:
//   bg #0D1117 · rose #FF6B9D · violet #7C3AED · lavender #BB86FC
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────────────────────────
  late AnimationController _heartCtrl;
  late Animation<double>   _heartScale;

  late AnimationController _entryCtrl;
  late Animation<double>   _entryFade;
  late Animation<double>   _entrySlide;

  late AnimationController _subtitleCtrl;
  late Animation<double>   _subtitleFade;



  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // 1 — Pulsing heart (loops forever until navigation)
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _heartScale = Tween<double>(begin: 1.0, end: 1.16).animate(
      CurvedAnimation(parent: _heartCtrl, curve: Curves.easeInOut),
    );

    // 2 — Heart + title slide up & fade in (runs once)
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _entryFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    );

    _entrySlide = Tween<double>(begin: 32, end: 0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut),
    );

    // 3 — Subtitle fades in slightly after the title
    _subtitleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _subtitleFade = CurvedAnimation(
      parent: _subtitleCtrl,
      curve: Curves.easeOut,
    );

    // Sequence the entrance
    _entryCtrl.forward().then((_) {
      if (mounted) _subtitleCtrl.forward();
    });

    _checkLogin();
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    _entryCtrl.dispose();
    _subtitleCtrl.dispose();
    super.dispose();
  }

  // ── Navigation logic ────────────────────────────────────────────────────────
  Future<void> _checkLogin() async {
    // Minimum 1.2s so the entrance animation plays smoothly.
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    final isLoggedIn = await Session.isLoggedIn();
    if (!isLoggedIn) {
      _navigate(const LoginScreen());
      return;
    }

    CallService.startIncomingCallWatcher();

    final token = (await Session.getToken())!;
    final userId = (await Session.getUserId())!;
    final cachedPartnerId = await Session.getCachedPartnerId();
    final cachedPartnerName = await Session.getCachedPartnerName() ?? "Partner";

    // Attempt to verify/refresh pair status from backend (with quick timeout)
    Map<String, dynamic>? pairStatus;
    try {
      pairStatus = await ApiService.getPairStatus(userId, token: token)
          .timeout(const Duration(milliseconds: 2500));
    } catch (_) {}

    if (!mounted) return;

    Widget targetScreen;
    if (pairStatus != null) {
      if (pairStatus["connected"] == true && pairStatus["partner_id"] != null) {
        final partnerId = pairStatus["partner_id"] as int;
        final partnerName = (pairStatus["partner_name"] ?? "Partner").toString();
        await Session.savePartner(partnerId, partnerName.isNotEmpty ? partnerName : "Partner");
        targetScreen = ChatScreen(
          partnerId: partnerId,
          partnerName: partnerName.isNotEmpty ? partnerName : "Partner",
        );
      } else {
        await Session.clearPartner();
        targetScreen = const HomeScreen();
      }
    } else {
      // Offline or network discovery in progress: seamlessly fallback to cached partner session!
      if (cachedPartnerId != null) {
        targetScreen = ChatScreen(
          partnerId: cachedPartnerId,
          partnerName: cachedPartnerName,
        );
      } else {
        targetScreen = const HomeScreen();
      }
    }

    final hasPasscode = await SecurityService.hasPasscode();
    if (!mounted) return;
    if (hasPasscode) {
      final nav = Navigator.of(context);
      nav.pushReplacement(
        PageRouteBuilder(
          pageBuilder: (ctx, anim1, anim2) => PasscodeSetupScreen(
            mode: PasscodeMode.unlock,
            onSuccess: () {
              nav.pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (c, a1, a2) => targetScreen,
                  transitionDuration: const Duration(milliseconds: 600),
                  transitionsBuilder: (c, animation, a2, child) => FadeTransition(
                    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    child: child,
                  ),
                ),
              );
            },
          ),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (ctx, animation, anim2, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
    } else {
      _navigate(targetScreen);
    }
  }

  // Smooth cross-fade instead of a jarring slide.
  void _navigate(Widget screen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: activeTheme.bg,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Entrance animation wraps emblem + title
                AnimatedBuilder(
                  animation: _entryCtrl,
                  builder: (_, child) => Opacity(
                    opacity: _entryFade.value,
                    child: Transform.translate(
                      offset: Offset(0, _entrySlide.value),
                      child: child,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Clean emblem
                      ScaleTransition(
                        scale: _heartScale,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: activeTheme.surfaceElevated,
                            shape: BoxShape.circle,
                            border: Border.all(color: activeTheme.border),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.lock_rounded,
                              size: 36,
                              color: activeTheme.primary,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Clean Title
                      Text(
                        "TwoOfUs",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: activeTheme.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Subtitle
                FadeTransition(
                  opacity: _subtitleFade,
                  child: Text(
                    "Private 1-to-1 encrypted messenger",
                    style: TextStyle(
                      color: activeTheme.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                // Animated loading dots
                FadeTransition(
                  opacity: _subtitleFade,
                  child: _LoadingDots(color: activeTheme.primary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Three pulsing dots that animate in a staggered wave.
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingDots extends StatefulWidget {
  final Color color;
  const _LoadingDots({required this.color});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (((_ctrl.value * 3) - i) % 3) / 3;
            final opacity = 0.2 + 0.8 * _sineWave(phase);
            final dy = -4.0 * _sineWave(phase);

            return Transform.translate(
              offset: Offset(0, dy),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: opacity),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  double _sineWave(double t) {
    if (t <= 0.5) return t / 0.5;
    return 1.0 - (t - 0.5) / 0.5;
  }
}
