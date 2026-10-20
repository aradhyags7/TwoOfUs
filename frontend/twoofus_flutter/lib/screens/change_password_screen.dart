import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../utils/session.dart';
import '../widgets/design_system/design_system.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — Change Password Screen
// ─────────────────────────────────────────────────────────────────────────────

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentController.addListener(_onTextChanged);
    _newController.addListener(_onTextChanged);
    _confirmController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _hasMinLength => _newController.text.length >= 8;
  bool get _hasUppercase => RegExp(r'[A-Z]').hasMatch(_newController.text);
  bool get _hasLowercase => RegExp(r'[a-z]').hasMatch(_newController.text);
  bool get _hasNumber => RegExp(r'[0-9]').hasMatch(_newController.text);
  bool get _hasSpecial => RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(_newController.text);
  bool get _passwordsMatch =>
      _newController.text.isNotEmpty && _newController.text == _confirmController.text;

  bool get _isFormValid =>
      _currentController.text.isNotEmpty &&
      _hasMinLength &&
      _hasUppercase &&
      _hasLowercase &&
      _hasNumber &&
      _hasSpecial &&
      _passwordsMatch;

  Future<void> _submitChangePassword() async {
    HapticFeedback.lightImpact();
    if (!_isFormValid) return;

    final userId = await Session.getUserId();
    if (!mounted) return;
    if (userId == null) {
      AppFeedback.showError(context, "Session expired. Please sign in again.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await ApiService.changePassword(
      userId,
      _currentController.text.trim(),
      _newController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      AppFeedback.showSuccess(
        context,
        "Password changed successfully",
        title: "Security Updated",
      );
      Navigator.pop(context);
    } else {
      setState(() {
        _errorMessage = "Current password is incorrect or server error occurred.";
      });
      AppFeedback.showError(
        context,
        "Failed to update password. Check your current password.",
      );
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
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Change Password",
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Emblem
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: activeTheme.surfaceRaised,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: activeTheme.border, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.key_rounded,
                          size: 26,
                          color: activeTheme.isDark ? activeTheme.accentBright : activeTheme.accentFill,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      "Update Master Password",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: activeTheme.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Choose a strong password with at least 8 characters.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: activeTheme.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Error Banner
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: activeTheme.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: activeTheme.danger.withValues(alpha: 0.4), width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, color: activeTheme.danger, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: activeTheme.danger,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Current Password
                    AppTextField(
                      controller: _currentController,
                      label: "Current Password",
                      hintText: "Enter existing account password",
                      isPassword: true,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),

                    // New Password
                    AppTextField(
                      controller: _newController,
                      label: "New Password",
                      hintText: "Enter new strong password",
                      isPassword: true,
                      prefixIcon: const Icon(Icons.shield_outlined, size: 18),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),

                    // Confirm Password
                    AppTextField(
                      controller: _confirmController,
                      label: "Confirm New Password",
                      hintText: "Re-enter new password",
                      isPassword: true,
                      prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitChangePassword(),
                    ),
                    const SizedBox(height: 24),

                    // Complexity Checklist Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: activeTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: activeTheme.border, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "PASSWORD REQUIREMENTS",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: activeTheme.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildRequirementRow(activeTheme, _hasMinLength, "At least 8 characters"),
                          _buildRequirementRow(activeTheme, _hasUppercase, "At least 1 uppercase letter (A-Z)"),
                          _buildRequirementRow(activeTheme, _hasLowercase, "At least 1 lowercase letter (a-z)"),
                          _buildRequirementRow(activeTheme, _hasNumber, "At least 1 digit (0-9)"),
                          _buildRequirementRow(activeTheme, _hasSpecial, "At least 1 special character (!@#\$%^&*)"),
                          _buildRequirementRow(activeTheme, _passwordsMatch, "Passwords match identically"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Submit Button
                    AppButton(
                      text: "Update Password",
                      isLoading: _isLoading,
                      onPressed: _isFormValid ? _submitChangePassword : null,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequirementRow(AppTheme theme, bool satisfied, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            satisfied ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: satisfied ? theme.success : theme.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: satisfied ? theme.textPrimary : theme.textTertiary,
                fontWeight: satisfied ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}