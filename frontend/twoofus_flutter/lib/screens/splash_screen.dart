import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/security_service.dart';
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

  // ── Palette ────────────────────────────────────────────────────────────────
  Color get _rose     => ThemeController.currentTheme.value.primary;
  Color get _violet   => ThemeController.currentTheme.value.secondary;
  Color get _lavender => ThemeController.currentTheme.value.gradientEnd;

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
        pageBuilder: (_, __, ___) => screen,
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
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
          body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Ambient corner glows ─────────────────────────────────────────
          Positioned(
            top: -100, left: -80,
            child: _Glow(color: _rose.withOpacity(0.13), size: 340),
          ),
          Positioned(
            bottom: -120, right: -100,
            child: _Glow(color: _violet.withOpacity(0.11), size: 380),
          ),

          // ── Center content ───────────────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Entrance animation wraps heart + title
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
                      // Pulsing gradient heart
                      ScaleTransition(
                        scale: _heartScale,
                        child: ShaderMask(
                          shaderCallback: (b) => LinearGradient(
                            colors: [_rose, _violet],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(b),
                          blendMode: BlendMode.srcIn,
                          child: const Icon(
                            Icons.favorite_rounded,
                            size: 92,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Gradient title
                      ShaderMask(
                        shaderCallback: (b) => LinearGradient(
                          colors: [_rose, _lavender],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ).createShader(b),
                        blendMode: BlendMode.srcIn,
                        child: const Text(
                          "TwoOfUs",
                          style: TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Subtitle fades in after the title
                FadeTransition(
                  opacity: _subtitleFade,
                  child: Text(
                    "Your private space, always ✨",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.38),
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),

                const SizedBox(height: 72),

                // Animated loading dots
                FadeTransition(
                  opacity: _subtitleFade,
                  child: const _LoadingDots(),
                ),
              ],
            ),
          ),
        ],
      ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Three pulsing dots that animate in a staggered wave.
// Self-contained so it manages its own AnimationController.
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

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
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot is offset by 1/3 of the cycle.
            final phase = (((_ctrl.value * 3) - i) % 3) / 3;
            // Smooth sine-like opacity: 0.2 → 1.0 → 0.2
            final opacity = 0.2 + 0.8 * _sineWave(phase);
            // Vertical bob matching the opacity
            final dy = -6.0 * _sineWave(phase);

            return Transform.translate(
              offset: Offset(0, dy),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF6B9D).withOpacity(opacity),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  /// Maps a value in [0,1] to a smooth [0,1] sine-like peak at 0.5.
  double _sineWave(double t) {
    // t in [0,1] → peak at 0.5
    if (t <= 0.5) return t / 0.5;
    return 1.0 - (t - 0.5) / 0.5;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Radial ambient glow (same helper used in Login / Home / Chat screens).
// ─────────────────────────────────────────────────────────────────────────────
class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
}
