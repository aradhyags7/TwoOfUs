import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/theme_controller.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmailOrUsername;

  const ForgotPasswordScreen({super.key, this.initialEmailOrUsername});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _newPassFocus = FocusNode();
  final _confirmPassFocus = FocusNode();

  int _currentStep = 1; // 1: Request code, 2: Enter code & new pass, 3: Success
  bool _isLoading = false;
  bool _obscureNewPass = true;
  bool _obscureConfirmPass = true;
  String? _targetEmail;

  // 60-second cooldown timer for resending email code
  int _resendCooldown = 0;
  Timer? _resendTimer;

  // ── Theme Accessors ───────────────────────────────────────────────────────
  Color get _bg => ThemeController.currentTheme.value.bg;
  Color get _surface => ThemeController.currentTheme.value.surface;
  Color get _rose => ThemeController.currentTheme.value.primary;
  Color get _violet => ThemeController.currentTheme.value.secondary;
  Color get _lavender => ThemeController.currentTheme.value.gradientEnd;
  bool get _isDark => ThemeController.currentTheme.value.textPrimary == Colors.white;

  Color get _text => _isDark ? Colors.white : const Color(0xFF1A0A2E);
  Color get _sub => _isDark
      ? Colors.white.withValues(alpha: 0.6)
      : Colors.black.withValues(alpha: 0.55);

  @override
  void initState() {
    super.initState();
    if (widget.initialEmailOrUsername != null && widget.initialEmailOrUsername!.isNotEmpty) {
      _emailCtrl.text = widget.initialEmailOrUsername!;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    _newPassFocus.dispose();
    _confirmPassFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() => _resendCooldown = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.mark_email_read_rounded,
              color: isError ? Colors.redAccent : Colors.pinkAccent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF200F35),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _requestCode() async {
    if (_resendCooldown > 0 && _currentStep == 2) return;
    final query = _emailCtrl.text.trim();
    if (query.isEmpty) {
      _toast("Please enter your email or username", isError: true);
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);

    final res = await ApiService.requestPasswordReset(query);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res != null && !res.containsKey("error")) {
      final fallback = res["fallback_code"]?.toString();
      setState(() {
        _targetEmail = res["email"]?.toString() ?? query;
        _currentStep = 2;
        if (fallback != null && fallback.isNotEmpty) {
          _codeCtrl.text = fallback;
        }
      });
      _startResendTimer();
      if (fallback != null && fallback.isNotEmpty) {
        _toast("📬 Code [$fallback] loaded automatically!");
      } else {
        _toast("Password reset email sent to ${_targetEmail ?? 'your email'}! 📬");
      }
    } else {
      final err = res?["error"]?.toString() ?? "Could not find an account with those details";
      _toast(err, isError: true);
    }
  }

  Future<void> _submitReset() async {
    final query = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final newPass = _newPassCtrl.text.trim();
    final confirmPass = _confirmPassCtrl.text.trim();

    if (code.isEmpty || code.length < 6) {
      _toast("Please enter the 6-digit reset code", isError: true);
      return;
    }
    if (newPass.length < 6) {
      _toast("Password must be at least 6 characters long", isError: true);
      return;
    }
    if (newPass != confirmPass) {
      _toast("Passwords do not match", isError: true);
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);

    final res = await ApiService.resetPassword(
      emailOrUsername: query,
      resetCode: code,
      newPassword: newPass,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res != null && !res.containsKey("error")) {
      setState(() => _currentStep = 3);
      HapticFeedback.heavyImpact();
    } else {
      final err = res?["error"]?.toString() ?? "Failed to reset password. Check your code.";
      _toast(err, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: _text, size: 20),
          onPressed: () {
            if (_currentStep == 2) {
              setState(() => _currentStep = 1);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildCurrentStepView(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 1:
        return _buildStep1Request();
      case 2:
        return _buildStep2VerifyAndReset();
      case 3:
        return _buildStep3Success();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 1: Request Code ─────────────────────────────────────────────────
  Widget _buildStep1Request() {
    return Column(
      key: const ValueKey("step1"),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_rose, _violet]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _rose.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          "Forgot Password? 🔐",
          style: TextStyle(
            color: _text,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Don't worry! Enter your registered email address or username to receive a 6-digit security reset code directly to your email.",
          style: TextStyle(color: _sub, fontSize: 14, height: 1.45),
        ),
        const SizedBox(height: 32),

        _buildField(
          controller: _emailCtrl,
          focusNode: _emailFocus,
          hint: "Email address or username",
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
        ),

        const SizedBox(height: 28),

        _buildGradientButton(
          label: "Send Reset Code to Email",
          icon: Icons.send_rounded,
          onTap: _isLoading ? null : _requestCode,
        ),
      ],
    );
  }

  // ── Step 2: Enter Code & New Password ────────────────────────────────────
  Widget _buildStep2VerifyAndReset() {
    return Column(
      key: const ValueKey("step2"),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_violet, _rose]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _violet.withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "Check Your Email 📬",
          style: TextStyle(
            color: _text,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "We have sent a 6-digit verification code to ${_targetEmail ?? 'your registered email'}.\nPlease check your inbox (and spam/junk folder), then enter the code below to reset your password:",
          style: TextStyle(color: _sub, fontSize: 13, height: 1.45),
        ),

        const SizedBox(height: 24),

        // 6-digit code input
        _buildField(
          controller: _codeCtrl,
          focusNode: _codeFocus,
          hint: "6-Digit Reset Code (e.g. 123456)",
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
        ),

        const SizedBox(height: 16),

        // New password
        _buildField(
          controller: _newPassCtrl,
          focusNode: _newPassFocus,
          hint: "New Password (min 6 characters)",
          icon: Icons.lock_outline_rounded,
          obscure: _obscureNewPass,
          suffix: IconButton(
            icon: Icon(
              _obscureNewPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: _sub,
              size: 20,
            ),
            onPressed: () => setState(() => _obscureNewPass = !_obscureNewPass),
          ),
        ),

        const SizedBox(height: 16),

        // Confirm new password
        _buildField(
          controller: _confirmPassCtrl,
          focusNode: _confirmPassFocus,
          hint: "Confirm New Password",
          icon: Icons.lock_reset_rounded,
          obscure: _obscureConfirmPass,
          suffix: IconButton(
            icon: Icon(
              _obscureConfirmPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: _sub,
              size: 20,
            ),
            onPressed: () => setState(() => _obscureConfirmPass = !_obscureConfirmPass),
          ),
        ),

        const SizedBox(height: 28),

        _buildGradientButton(
          label: "Update & Set Password",
          icon: Icons.check_circle_outline_rounded,
          onTap: _isLoading ? null : _submitReset,
        ),

        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: (_isLoading || _resendCooldown > 0) ? null : _requestCode,
            icon: Icon(Icons.refresh_rounded, color: _resendCooldown > 0 ? _sub.withValues(alpha: 0.4) : _sub, size: 16),
            label: Text(
              _resendCooldown > 0
                  ? "Resend Email Code in ${_resendCooldown}s"
                  : "Resend Code to Email",
              style: TextStyle(
                color: _resendCooldown > 0 ? _sub.withValues(alpha: 0.4) : _sub,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 3: Success Screen ───────────────────────────────────────────────
  Widget _buildStep3Success() {
    return Column(
      key: const ValueKey("step3"),
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00B0FF)]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 54),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          "Password Changed! 🎉",
          style: TextStyle(
            color: _text,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Your password has been successfully updated with end-to-end encryption security. You can now log into your TwoOfUs space.",
          style: TextStyle(color: _sub, fontSize: 14, height: 1.45),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        _buildGradientButton(
          label: "Back to Login",
          icon: Icons.login_rounded,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: TextStyle(color: _text, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: _sub.withValues(alpha: 0.6), fontSize: 14),
          prefixIcon: Icon(icon, color: _rose, size: 20),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: onTap == null ? [Colors.grey.shade700, Colors.grey.shade800] : [_rose, _violet],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: onTap == null
            ? []
            : [
                BoxShadow(
                  color: _rose.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
