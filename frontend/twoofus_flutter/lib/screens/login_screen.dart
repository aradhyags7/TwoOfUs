import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  bool obscurePassword = true;
  bool isLoading = false;

  // ── Palette ──────────────────────────────────────────────────────────────
  Color get _bg       => ThemeController.currentTheme.value.bg;
  Color get _surface  => ThemeController.currentTheme.value.surface;
  Color get _rose     => ThemeController.currentTheme.value.primary;
  Color get _violet   => ThemeController.currentTheme.value.secondary;
  Color get _lavender => ThemeController.currentTheme.value.gradientEnd;
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    emailFocus.addListener(() => setState(() {}));
    passwordFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  Future<void> login() async {
    HapticFeedback.lightImpact();
    setState(() => isLoading = true);
    try {
      final result = await ApiService.login(
        emailController.text.trim(),
        passwordController.text.trim(),
      );

      if (!mounted) return;

      if (result != null && result.containsKey("access_token")) {
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(
          "token",
          result["access_token"],
        );

        await prefs.setInt(
          "user_id",
          result["user_id"],
        );

        await prefs.setString(
          "email",
          result["email"],
        );

        await prefs.setString(
          "username",
          result["username"],
        );

        if (!mounted) return;

        final pairStatus = await ApiService.getPairStatus(
          result["user_id"],
          token: result["access_token"],
        );

        if (!mounted) return;

        if (pairStatus != null &&
            pairStatus["connected"] == true &&
            pairStatus["partner_id"] != null) {
          final partnerId = pairStatus["partner_id"] as int;
          final partnerName = (pairStatus["partner_name"] ?? "Partner").toString();

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                partnerId: partnerId,
                partnerName: partnerName.isNotEmpty ? partnerName : "Partner",
              ),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const HomeScreen(),
            ),
          );
        }
      } else {
        final errMsg = (result != null && result.containsKey("error"))
            ? result["error"].toString()
            : "Hmm, those credentials don't match";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            backgroundColor: const Color(0xFF2A1040),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
    setState(() => isLoading = false);
  }

  // ── Reusable animated field ───────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    final focused = focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _surface,
        border: Border.all(
          color: focused ? _rose.withOpacity(0.8) : Colors.white.withOpacity(0.07),
          width: focused ? 1.5 : 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: _rose.withOpacity(0.12),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        cursorColor: _rose,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.28),
            fontSize: 15,
          ),
          prefixIcon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Icon(
              icon,
              key: ValueKey(focused),
              color: focused ? _rose : Colors.white.withOpacity(0.28),
              size: 20,
            ),
          ),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: activeTheme.bg,
          body: Stack(
        children: [
          // ── Ambient corner glows ──────────────────────────────────────────
          Positioned(
            top: -100,
            left: -80,
            child: _Glow(color: _rose.withOpacity(0.13), size: 340),
          ),
          Positioned(
            bottom: -120,
            right: -100,
            child: _Glow(color: _violet.withOpacity(0.11), size: 380),
          ),

          // ── Main content ─────────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: SizedBox(
                height: MediaQuery.of(context).size.height - 60,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Pulsing gradient heart — the signature element
                   const Icon(
                    Icons.favorite_rounded,
                    size: 68,
                    color: Colors.pink,
                    ),

                    const SizedBox(height: 16),

                    // Gradient app name
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [_rose, _lavender],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ).createShader(bounds),
                      blendMode: BlendMode.srcIn,
                      child: const Text(
                        "TwoOfUs",
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Colors.white, // overridden by ShaderMask
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      "Your private space, always ✨",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.38),
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),

                    const SizedBox(height: 52),

                    // Email field
                    _buildField(
                      controller: emailController,
                      focusNode: emailFocus,
                      hint: "Email address or Username",
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),

                    const SizedBox(height: 14),

                    // Password field
                    _buildField(
                      controller: passwordController,
                      focusNode: passwordFocus,
                      hint: "Password",
                      icon: Icons.lock_outline_rounded,
                      obscure: obscurePassword,
                      suffix: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.white.withOpacity(0.3),
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => obscurePassword = !obscurePassword),
                      ),
                    ),

                    // Forgot password — right-aligned, subtle
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ForgotPasswordScreen(
                                initialEmailOrUsername: emailController.text.trim(),
                              ),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                        ),
                        child: Text(
                          "Forgot password?",
                          style: TextStyle(
                            color: _rose.withValues(alpha: 0.8),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── Gradient sign-in button ──────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: isLoading
                              ? null
                              : LinearGradient(
                                  colors: [_rose, _violet],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                          color: isLoading ? _surface : null,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: isLoading
                              ? []
                              : [
                                  BoxShadow(
                                    color: _rose.withOpacity(0.38),
                                    blurRadius: 22,
                                    offset: const Offset(0, 7),
                                  ),
                                ],
                        ),
                        child: ElevatedButton(
                          onPressed: isLoading ? null : login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  "Sign in",
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Create account row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "New here?  ",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.38),
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                          child: Text(
                            "Create your space",
                            style: TextStyle(
                              color: _rose,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
        );
      },
    );
  }
}

// ── Helper widget: radial ambient glow blob ───────────────────────────────────
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