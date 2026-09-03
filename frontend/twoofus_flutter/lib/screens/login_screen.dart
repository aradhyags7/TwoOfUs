import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import '../widgets/server_config_dialog.dart';

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

  Future<void> _handleSuccessfulAuth(Map<String, dynamic> authData) async {
    await Session.saveLogin(
      token: authData["access_token"],
      userId: authData["user_id"],
      username: authData["username"],
      email: authData["email"],
    );

    CallService.startIncomingCallWatcher();

    if (!mounted) return;

    final pairStatus = await ApiService.getPairStatus(
      authData["user_id"],
      token: authData["access_token"],
    );

    if (!mounted) return;

    if (pairStatus != null &&
        pairStatus["connected"] == true &&
        pairStatus["partner_id"] != null) {
      final partnerId = pairStatus["partner_id"] as int;
      final partnerName = (pairStatus["partner_name"] ?? "Partner").toString();
      await Session.savePartner(partnerId, partnerName);

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
  }

  void _show2FALoginSheet(String tempToken, {String? fallbackCode}) {
    final codeCtrl = TextEditingController(text: fallbackCode ?? '');
    bool isVerifying = false;
    bool isSendingEmail = false;
    int emailCooldown = 0;
    String? errorText;
    String? successText = (fallbackCode != null && fallbackCode.isNotEmpty)
        ? "📬 Code [$fallbackCode] loaded automatically!"
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16082A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4081).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_rounded, color: Color(0xFFFF4081), size: 32),
                ),
                const SizedBox(height: 14),
                const Text(
                  "Two-Factor Authentication",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Enter the 6-digit code from your Authenticator app, Email, or an 8-character backup recovery code:",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: codeCtrl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                  decoration: InputDecoration(
                    hintText: "123456 / CODE-1234",
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 13,
                      letterSpacing: 2,
                    ),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFFF4081), width: 2),
                    ),
                    errorText: errorText,
                  ),
                ),
                if (successText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    successText!,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isVerifying
                        ? null
                        : () async {
                            final code = codeCtrl.text.trim();
                            if (code.isEmpty) return;
                            setSheetState(() {
                              isVerifying = true;
                              errorText = null;
                            });

                            final verifyRes = await ApiService.verify2FALogin(
                              tempToken: tempToken,
                              code: code,
                            );

                            if (!mounted) return;

                            if (verifyRes != null && verifyRes.containsKey("access_token")) {
                              Navigator.pop(sheetCtx);
                              await _handleSuccessfulAuth(verifyRes);
                            } else {
                              setSheetState(() {
                                isVerifying = false;
                                errorText = verifyRes?["error"] ?? "Invalid code. Try again.";
                              });
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4081),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: isVerifying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            "Verify & Log In",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Send to Email Alternative Button
                TextButton.icon(
                  onPressed: (isSendingEmail || emailCooldown > 0)
                      ? null
                      : () async {
                          setSheetState(() {
                            isSendingEmail = true;
                            errorText = null;
                          });
                          final res = await ApiService.send2FAEmailCode(tempToken: tempToken);
                          setSheetState(() => isSendingEmail = false);
                          if (res != null && !res.containsKey("error")) {
                            setSheetState(() {
                              emailCooldown = 60;
                              final fallback = res["fallback_code"]?.toString();
                              if (fallback != null && fallback.isNotEmpty) {
                                codeCtrl.text = fallback;
                                successText = "📬 Code [$fallback] loaded automatically!";
                              } else {
                                successText = "📬 Code sent to ${res['email'] ?? 'your email'}!";
                              }
                            });
                          } else {
                            setSheetState(() {
                              errorText = res?["error"] ?? "Failed to send email code.";
                            });
                          }
                        },
                  icon: isSendingEmail
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                        )
                      : const Icon(Icons.mail_outline_rounded, size: 16, color: Colors.white70),
                  label: Text(
                    emailCooldown > 0
                        ? "Resend email code in ${emailCooldown}s"
                        : "Send verification code to my email",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          );
        },
      ),
    );
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

      if (result != null && result["requires_2fa"] == true) {
        final tempToken = result["temp_token"] as String;
        final fallbackCode = result["fallback_code"]?.toString();
        _show2FALoginSheet(tempToken, fallbackCode: fallbackCode);
      } else if (result != null && result.containsKey("access_token")) {
        await _handleSuccessfulAuth(result);
      } else {
        final errMsg = (result != null && result.containsKey("error"))
            ? result["error"].toString()
            : "Hmm, those credentials don't match";
        final isConnError = errMsg.contains("Cannot connect") || errMsg.contains("backend connection");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            backgroundColor: const Color(0xFF2A1040),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: isConnError
                ? SnackBarAction(
                    label: "Server IP ⚙️",
                    textColor: Colors.amberAccent,
                    onPressed: () => ServerConfigDialog.show(context),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          action: SnackBarAction(
            label: "Server IP ⚙️",
            textColor: Colors.amberAccent,
            onPressed: () => ServerConfigDialog.show(context),
          ),
        ),
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

          // ── Server IP settings button ────────────────────────────────────
          Positioned(
            top: 44,
            right: 18,
            child: SafeArea(
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(Icons.dns_rounded, color: Colors.white70, size: 18),
                ),
                tooltip: "Server Configuration",
                onPressed: () => ServerConfigDialog.show(context),
              ),
            ),
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