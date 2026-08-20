import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final usernameFocus = FocusNode();
  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  bool obscurePassword = true;
  bool isLoading = false;

  // ── Palette ───────────────────────────────────────────────────────────────
  Color get _bg       => ThemeController.currentTheme.value.bg;
  Color get _surface  => ThemeController.currentTheme.value.surface;
  Color get _rose     => ThemeController.currentTheme.value.primary;
  Color get _violet   => ThemeController.currentTheme.value.secondary;
  Color get _lavender => ThemeController.currentTheme.value.gradientEnd;
  // ──────────────────────────────────────────────────────────────────────────

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    usernameFocus.addListener(() => setState(() {}));
    emailFocus.addListener(() => setState(() {}));
    passwordFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    usernameFocus.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFF2A1040) : _rose,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> register() async {
    HapticFeedback.lightImpact();
    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    // Validate locally BEFORE hitting the network.
    if (username.isEmpty) {
      _showSnack("Please choose a username", isError: true);
      return;
    }
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      _showSnack("Please enter a valid email address", isError: true);
      return;
    }
    if (password.length < 6) {
      _showSnack("Password must be at least 6 characters", isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await ApiService.register(email, username, password);

      if (!mounted) return;

      if (result != null) {
        _showSnack("Your space is ready ❤️");
        Navigator.pop(context);
      } else {
        _showSnack("Something went wrong — try again", isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Reusable animated field (same as LoginScreen) ─────────────────────────
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
          color: focused
              ? _rose.withOpacity(0.8)
              : Colors.white.withOpacity(0.07),
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
          // ── Ambient corner glows (flipped vs LoginScreen) ────────────────
          Positioned(
            top: -80,
            right: -60,
            child: _Glow(color: _violet.withOpacity(0.12), size: 320),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: _Glow(color: _rose.withOpacity(0.10), size: 360),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Custom back button ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 8),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // ── Scrollable form ──────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),

                        // Icon badge
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: _rose.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: _rose,
                            size: 26,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Gradient heading
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [_rose, _lavender],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(bounds),
                          blendMode: BlendMode.srcIn,
                          child: const Text(
                            "Create your\nspace",
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          "Just the two of you — always private.",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.38),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Username field
                        _buildField(
                          controller: usernameController,
                          focusNode: usernameFocus,
                          hint: "Username",
                          icon: Icons.person_outline_rounded,
                        ),

                        const SizedBox(height: 14),

                        // Email field
                        _buildField(
                          controller: emailController,
                          focusNode: emailFocus,
                          hint: "Email address",
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
                            onPressed: () => setState(
                              () => obscurePassword = !obscurePassword,
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Gradient create button
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
                              onPressed: isLoading ? null : register,
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
                                      "Create account",
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

                        const SizedBox(height: 28),

                        // Already have account
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Already have a space?  ",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.38),
                                fontSize: 14,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Text(
                                "Sign in",
                                style: TextStyle(
                                  color: _rose,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
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

// ── Helper: radial ambient glow blob ─────────────────────────────────────────
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