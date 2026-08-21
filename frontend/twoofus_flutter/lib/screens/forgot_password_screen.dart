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
  String? _generatedCode;

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
    super.dispose();
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
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

    if (res != null && res.containsKey("reset_code")) {
      setState(() {
        _targetEmail = res["email"]?.toString() ?? query;
        _generatedCode = res["reset_code"]?.toString();
        _currentStep = 2;
      });
      _toast("Reset code generated! Check your email or code banner ❤️");
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
      HapticFeedback.mediumImpact();
    } else {
      final err = res?["error"]?.toString() ?? "Failed to reset password";
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
          "Don't worry! Enter your registered email address or username to receive a 6-digit security reset code.",
          style: TextStyle(color: _sub, fontSize: 14, height: 1.45),
        ),
        const SizedBox(height: 32),

        _buildField(
          controller: _emailCtrl,
          focusNode: _emailFocus,
          hint: "Email or Username",
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
        ),

        const SizedBox(height: 28),

        _buildGradientButton(
          label: "Send Reset Code",
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
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_violet, _lavender]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _violet.withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.key_rounded, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "Reset Your Password 🔑",
          style: TextStyle(
            color: _text,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "We generated a 6-digit verification code for ${_targetEmail ?? 'your account'}.",
          style: TextStyle(color: _sub, fontSize: 13, height: 1.4),
        ),

        // Development/Local auto-fill hint card
        if (_generatedCode != null) ...[
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              setState(() => _codeCtrl.text = _generatedCode!);
              HapticFeedback.lightImpact();
              _toast("Code copied into input!");
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _rose.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _rose.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Security Code: $_generatedCode (Tap to auto-fill)",
                      style: TextStyle(color: _rose, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // 6-digit code input
        _buildField(
          controller: _codeCtrl,
          focusNode: _codeFocus,
          hint: "6-Digit Reset Code",
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
            onPressed: _isLoading ? null : _requestCode,
            icon: Icon(Icons.refresh_rounded, color: _sub, size: 16),
            label: Text("Resend Code", style: TextStyle(color: _sub, fontSize: 13)),
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

  // ── UI Components ────────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focusNode.hasFocus ? _rose : Colors.white.withValues(alpha: 0.08),
          width: focusNode.hasFocus ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: TextStyle(color: _text, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: _sub.withValues(alpha: 0.5), fontSize: 14),
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
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: onTap != null ? LinearGradient(colors: [_rose, _violet]) : null,
          color: onTap == null ? _surface : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                    color: _rose.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
