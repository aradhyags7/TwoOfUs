import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../widgets/design_system/design_system.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — Forgot Password & Password Recovery Screen
// ─────────────────────────────────────────────────────────────────────────────

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmailOrUsername;

  const ForgotPasswordScreen({super.key, this.initialEmailOrUsername});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
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
  String? _targetEmail;
  String? _errorMessage;

  // 60-second cooldown timer for resending email code
  int _resendCooldown = 0;
  Timer? _resendTimer;

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

  Future<void> _requestCode() async {
    HapticFeedback.lightImpact();
    if (_resendCooldown > 0 && _currentStep == 2) return;
    final query = _emailCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _errorMessage = "Please enter your email or username");
      AppFeedback.showError(context, "Please enter your email or username");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ApiService.requestPasswordReset(query);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res != null && res["success"] == true) {
      setState(() {
        _targetEmail = res["masked_email"] ?? query;
        _currentStep = 2;
      });
      _startResendTimer();
      AppFeedback.showSuccess(
        context,
        "A 6-digit reset code has been sent to ${_targetEmail ?? 'your email'}",
        title: "Code Dispatched",
      );
    } else {
      final err = res?["error"] ?? "Failed to send reset code. Please check your credentials.";
      setState(() => _errorMessage = err);
      AppFeedback.showError(context, err);
    }
  }

  Future<void> _verifyAndReset() async {
    HapticFeedback.lightImpact();
    final query = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final newPass = _newPassCtrl.text.trim();
    final confirmPass = _confirmPassCtrl.text.trim();

    if (code.isEmpty || code.length != 6) {
      setState(() => _errorMessage = "Please enter the 6-digit verification code");
      AppFeedback.showError(context, "Please enter the 6-digit verification code");
      return;
    }

    if (newPass.length < 6) {
      setState(() => _errorMessage = "Password must be at least 6 characters long");
      AppFeedback.showError(context, "Password must be at least 6 characters long");
      return;
    }

    if (newPass != confirmPass) {
      setState(() => _errorMessage = "Passwords do not match");
      AppFeedback.showError(context, "Passwords do not match");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ApiService.resetPassword(
      emailOrUsername: query,
      resetCode: code,
      newPassword: newPass,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res != null && res["success"] == true) {
      _resendTimer?.cancel();
      setState(() => _currentStep = 3);
      AppFeedback.showSuccess(
        context,
        "Your password has been reset successfully.",
        title: "Success",
      );
    } else {
      final err = res?["error"] ?? "Invalid or expired code. Please try again.";
      setState(() => _errorMessage = err);
      AppFeedback.showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: activeTheme.bg,
          appBar: AppBar(
            backgroundColor: activeTheme.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: activeTheme.textPrimary),
              onPressed: () {
                if (_currentStep == 2) {
                  setState(() => _currentStep = 1);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            title: Text(
              "Account Recovery",
              style: TextStyle(
                fontFamily: 'Inter',
                color: activeTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildCurrentStep(activeTheme),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentStep(AppTheme theme) {
    switch (_currentStep) {
      case 1:
        return _buildStep1Request(theme);
      case 2:
        return _buildStep2VerifyAndReset(theme);
      case 3:
      default:
        return _buildStep3Success(theme);
    }
  }

  Widget _buildStep1Request(AppTheme theme) {
    return Column(
      key: const ValueKey("step1"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.border, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.lock_reset_rounded,
              size: 26,
              color: theme.isDark ? theme.accentBright : theme.accentFill,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          "Reset Your Password",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Enter your registered email address or username. We'll send you a 6-digit verification code.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            color: theme.textTertiary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),

        if (_errorMessage != null) ...[
          _buildErrorBanner(theme, _errorMessage!),
          const SizedBox(height: 16),
        ],

        AppTextField(
          controller: _emailCtrl,
          focusNode: _emailFocus,
          label: "Email or Username",
          hintText: "Enter your account email or username",
          prefixIcon: const Icon(Icons.alternate_email_rounded, size: 18),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _requestCode(),
        ),
        const SizedBox(height: 24),

        AppButton(
          text: "Send Verification Code",
          isLoading: _isLoading,
          onPressed: _requestCode,
        ),
      ],
    );
  }

  Widget _buildStep2VerifyAndReset(AppTheme theme) {
    return Column(
      key: const ValueKey("step2"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.border, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.mark_email_read_rounded,
              size: 26,
              color: theme.isDark ? theme.accentBright : theme.accentFill,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          "Check Your Email",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "We sent a 6-digit code to ${_targetEmail ?? 'your email'}.\nEnter it below along with your new password.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            color: theme.textTertiary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),

        if (_errorMessage != null) ...[
          _buildErrorBanner(theme, _errorMessage!),
          const SizedBox(height: 16),
        ],

        AppTextField(
          controller: _codeCtrl,
          focusNode: _codeFocus,
          label: "6-Digit Verification Code",
          hintText: "e.g. 123456",
          prefixIcon: const Icon(Icons.pin_outlined, size: 18),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),

        AppTextField(
          controller: _newPassCtrl,
          focusNode: _newPassFocus,
          label: "New Password",
          hintText: "Minimum 6 characters",
          isPassword: true,
          prefixIcon: const Icon(Icons.shield_outlined, size: 18),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),

        AppTextField(
          controller: _confirmPassCtrl,
          focusNode: _confirmPassFocus,
          label: "Confirm New Password",
          hintText: "Re-enter new password",
          isPassword: true,
          prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _verifyAndReset(),
        ),
        const SizedBox(height: 20),

        Center(
          child: TextButton.icon(
            onPressed: (_resendCooldown > 0 || _isLoading) ? null : _requestCode,
            icon: Icon(
              Icons.replay_rounded,
              size: 16,
              color: _resendCooldown > 0 ? theme.textTertiary : (theme.isDark ? theme.accentBright : theme.accentFill),
            ),
            label: Text(
              _resendCooldown > 0 ? "Resend code in ${_resendCooldown}s" : "Resend code",
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: _resendCooldown > 0 ? theme.textTertiary : (theme.isDark ? theme.accentBright : theme.accentFill),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        AppButton(
          text: "Set New Password",
          isLoading: _isLoading,
          onPressed: _verifyAndReset,
        ),
      ],
    );
  }

  Widget _buildStep3Success(AppTheme theme) {
    return Column(
      key: const ValueKey("step3"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: theme.success.withValues(alpha: 0.4), width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.check_rounded, color: theme.success, size: 32),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "Password Reset Complete!",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Your password has been successfully updated. You can now sign in using your new credentials.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            color: theme.textTertiary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),

        AppButton(
          text: "Sign In Now",
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(AppTheme theme, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.danger.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: theme.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Inter',
                color: theme.danger,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
