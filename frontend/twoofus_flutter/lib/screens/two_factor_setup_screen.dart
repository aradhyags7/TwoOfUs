import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../widgets/design_system/app_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — Two-Factor Authentication Setup (Design System)
// ─────────────────────────────────────────────────────────────────────────────

class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  String? _secret;
  String? _otpauthUrl;
  String? _userEmail;
  List<String> _backupCodes = [];

  // Selected method: 0 = Authenticator App (TOTP), 1 = Email OTP
  int _selectedMethod = 0;

  // Step: 0 = Method Setup & OTP Confirmation, 1 = Recovery Codes Display
  int _currentStep = 0;
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  bool _isSubmitting = false;
  bool _copiedSecret = false;
  bool _copiedBackupCodes = false;

  // Email OTP timer & state
  bool _isSendingEmail = false;
  int _emailCooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
    _fetchSetupDetails();
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _codeFocusNode.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _onCodeChanged() {
    setState(() {});
    // Auto-submit when user reaches 6 digits
    if (_codeController.text.trim().length == 6 && !_isSubmitting && _currentStep == 0) {
      _submitVerification();
    }
  }

  Future<void> _fetchSetupDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ApiService.setup2FA();
    if (!mounted) return;

    if (res != null && res.containsKey("secret")) {
      setState(() {
        _secret = res["secret"];
        _otpauthUrl = res["otpauth_url"];
        _userEmail = res["email"];
        _backupCodes = List<String>.from(res["backup_codes"] ?? []);
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = res?["error"] ?? "Failed to initialize 2FA setup";
        _isLoading = false;
      });
    }
  }

  void _startCooldownTimer() {
    setState(() => _emailCooldownSeconds = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_emailCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _emailCooldownSeconds = 0);
      } else {
        setState(() => _emailCooldownSeconds--);
      }
    });
  }

  Future<void> _sendEmailOtp() async {
    if (_emailCooldownSeconds > 0 || _isSendingEmail) return;
    setState(() => _isSendingEmail = true);
    HapticFeedback.lightImpact();

    final res = await ApiService.send2FAEmailCode();
    if (!mounted) return;
    setState(() => _isSendingEmail = false);

    if (res != null && !res.containsKey("error")) {
      _startCooldownTimer();
      AppFeedback.showSuccess(
        context,
        "6-digit code sent to ${_userEmail ?? 'your email'}",
        title: "Code Dispatched",
      );
      _codeFocusNode.requestFocus();
    } else {
      AppFeedback.showError(
        context,
        res?["error"] ?? "Failed to send email verification code",
        title: "Delivery Failed",
      );
    }
  }

  Future<void> _submitVerification() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      AppFeedback.showError(
        context,
        "Please enter the complete 6-digit verification code",
        title: "Incomplete Code",
      );
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.lightImpact();

    final isTotp = _selectedMethod == 0;
    final res = await ApiService.enable2FA(
      method: isTotp ? "totp" : "email",
      code: code,
      secret: isTotp ? _secret : null,
      backupCodes: _backupCodes,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res != null && !res.containsKey("error")) {
      HapticFeedback.heavyImpact();
      setState(() {
        _currentStep = 1;
      });
    } else {
      AppFeedback.showError(
        context,
        res?["error"] ?? "Invalid verification code. Please check and try again.",
        title: "Verification Failed",
      );
    }
  }

  void _copySecret() {
    if (_secret == null) return;
    Clipboard.setData(ClipboardData(text: _secret!));
    HapticFeedback.selectionClick();
    setState(() => _copiedSecret = true);
    AppFeedback.showSuccess(context, "Setup key copied to clipboard");
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copiedSecret = false);
    });
  }

  void _copyAllBackupCodes() {
    if (_backupCodes.isEmpty) return;
    final all = _backupCodes.join("\n");
    Clipboard.setData(ClipboardData(text: all));
    HapticFeedback.mediumImpact();
    setState(() => _copiedBackupCodes = true);
    AppFeedback.showSuccess(context, "All 8 recovery codes copied to clipboard");
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
              onPressed: () => Navigator.pop(context, _currentStep == 1),
            ),
            title: Text(
              "Two-Factor Security",
              style: TextStyle(
                fontFamily: 'Inter',
                color: activeTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: activeTheme.accentFill,
                    strokeWidth: 2.5,
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded, color: activeTheme.danger, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: activeTheme.textSecondary,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            AppButton(
                              text: "Retry Setup",
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              onPressed: _fetchSetupDetails,
                            ),
                          ],
                        ),
                      ),
                    )
                  : _currentStep == 0
                      ? _buildSetupStep(activeTheme)
                      : _buildBackupCodesStep(activeTheme),
        );
      },
    );
  }

  Widget _buildSetupStep(AppTheme theme) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Step 1 of 2 Indicator
          _buildProgressPill(step: 1, total: 2, label: "Verification Setup", theme: theme),
          const SizedBox(height: 16),

          // Hero Icon & Title
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: theme.surfaceRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.border, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.shield_rounded,
              color: theme.isDark ? theme.accentBright : theme.accentFill,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "Protect Your Account",
            style: TextStyle(
              fontFamily: 'Inter',
              color: theme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Add a layer of defense against unauthorized logins using an authenticator app or email verification.",
            style: TextStyle(
              fontFamily: 'Inter',
              color: theme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),

          // Segmented Method Selector
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.border, width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _methodTab(
                    index: 0,
                    icon: Icons.qr_code_scanner_rounded,
                    label: "Authenticator",
                    theme: theme,
                  ),
                ),
                Expanded(
                  child: _methodTab(
                    index: 1,
                    icon: Icons.alternate_email_rounded,
                    label: "Email Code",
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Active Method Card
          if (_selectedMethod == 0)
            _buildAuthenticatorAppCard(theme)
          else
            _buildEmailOtpCard(theme),

          const SizedBox(height: 24),

          // 6-Box PIN Code Input
          _buildPinInputSection(theme),

          const SizedBox(height: 24),

          // Verify & Activate Button
          AppButton(
            text: _selectedMethod == 0 ? "Verify & Enable Authenticator" : "Verify & Enable Email 2FA",
            isFullWidth: true,
            isLoading: _isSubmitting,
            onPressed: (_isSubmitting || _codeController.text.trim().length != 6)
                ? null
                : _submitVerification,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildProgressPill({
    required int step,
    required int total,
    required String label,
    required AppTheme theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: theme.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: theme.accentFill.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "STEP $step OF $total",
              style: TextStyle(
                fontFamily: 'Inter',
                color: theme.isDark ? theme.accentBright : theme.accentFill,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              color: theme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodTab({
    required int index,
    required IconData icon,
    required String label,
    required AppTheme theme,
  }) {
    final isSelected = _selectedMethod == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedMethod = index;
          _codeController.clear();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? theme.accentFill : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? theme.onAccent : theme.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                color: isSelected ? theme.onAccent : theme.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthenticatorAppCard(AppTheme theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: theme.accentFill.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  "1",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.isDark ? theme.accentBright : theme.accentFill,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Scan QR Code with Authenticator",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Compatible with Google Authenticator, Microsoft Authenticator, Apple Passwords, or 1Password.",
              style: TextStyle(
                fontFamily: 'Inter',
                color: theme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Rendered QR Code
          if (_otpauthUrl != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.border, width: 1),
              ),
              child: QrImageView(
                data: _otpauthUrl!,
                version: QrVersions.auto,
                size: 160,
                backgroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 20),

          // Step 2: Manual Key Fallback
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: theme.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.border, width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  "2",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Can't scan? Copy setup key manually",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.border, width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _secret ?? "••••••••••••",
                    style: TextStyle(
                      color: theme.isDark ? theme.accentBright : theme.accentFill,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                InkWell(
                  onTap: _copySecret,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _copiedSecret
                          ? theme.success.withValues(alpha: 0.15)
                          : theme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.border, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copiedSecret ? Icons.check_circle_rounded : Icons.copy_rounded,
                          color: _copiedSecret ? theme.success : theme.textSecondary,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _copiedSecret ? "Copied" : "Copy",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: _copiedSecret ? theme.success : theme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
  }

  Widget _buildEmailOtpCard(AppTheme theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.border, width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.mark_email_read_rounded,
                  color: theme.isDark ? theme.accentBright : theme.accentFill,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Email Verification Code",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: theme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userEmail ?? "Your registered email",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            "When enabled, signing in will require a 6-digit code delivered to your registered email address.",
            style: TextStyle(
              fontFamily: 'Inter',
              color: theme.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            text: _emailCooldownSeconds > 0
                ? "Resend Code in ${_emailCooldownSeconds}s"
                : "Send 6-Digit Code to Email",
            variant: AppButtonVariant.secondary,
            isFullWidth: true,
            icon: _isSendingEmail
                ? null
                : const Icon(Icons.send_rounded, size: 16),
            isLoading: _isSendingEmail,
            onPressed: (_emailCooldownSeconds > 0 || _isSendingEmail) ? null : _sendEmailOtp,
          ),
        ],
      ),
    );
  }

  // 6-Box PIN Code View
  Widget _buildPinInputSection(AppTheme theme) {
    final code = _codeController.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            _selectedMethod == 0
                ? "ENTER 6-DIGIT CODE FROM AUTHENTICATOR"
                : "ENTER 6-DIGIT CODE FROM EMAIL",
            style: TextStyle(
              fontFamily: 'Inter',
              color: theme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),

        // Stacked Custom 6-Box Digit View with hidden TextField
        GestureDetector(
          onTap: () => _codeFocusNode.requestFocus(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _codeFocusNode.hasFocus
                    ? theme.accentFill
                    : theme.border,
                width: 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Display 6 boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    final isFilled = index < code.length;
                    final isFocusedBox = _codeFocusNode.hasFocus && index == code.length;
                    final char = isFilled ? code[index] : "";

                    return Container(
                      width: 44,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.surfaceRaised,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isFocusedBox
                              ? theme.accentFill
                              : (isFilled ? theme.accentFill.withValues(alpha: 0.6) : theme.border),
                          width: isFocusedBox ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        char,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: theme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }),
                ),

                // Invisible TextField overlaying
                Opacity(
                  opacity: 0.0,
                  child: TextField(
                    controller: _codeController,
                    focusNode: _codeFocusNode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    autofocus: false,
                    decoration: const InputDecoration(
                      counterText: "",
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Step 2: Backup Recovery Codes
  Widget _buildBackupCodesStep(AppTheme theme) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProgressPill(step: 2, total: 2, label: "Save Emergency Codes", theme: theme),
          const SizedBox(height: 18),

          // Success Hero Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.success.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.success.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.check_circle_rounded, color: theme.success, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedMethod == 0
                            ? "Authenticator Connected!"
                            : "Email 2FA Activated!",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: theme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Your account is now guarded by two-factor authentication.",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Recovery Codes Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.border, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_reset_rounded,
                  color: theme.isDark ? theme.accentBright : theme.accentFill,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Emergency Recovery Codes",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: theme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Each single-use code can be used to log in if you lose phone or email access. Store them safely in a password manager.",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: theme.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Codes Grid Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.border, width: 1),
            ),
            child: Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 3.2,
                  ),
                  itemCount: _backupCodes.length,
                  itemBuilder: (context, index) {
                    return Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: theme.surfaceRaised,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.border, width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${(index + 1).toString().padLeft(2, '0')}. ",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: theme.textTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _backupCodes[index],
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                AppButton(
                  text: _copiedBackupCodes ? "Recovery Codes Copied!" : "Copy All 8 Codes",
                  variant: AppButtonVariant.secondary,
                  isFullWidth: true,
                  icon: Icon(
                    _copiedBackupCodes ? Icons.check_circle_rounded : Icons.copy_all_rounded,
                    size: 16,
                  ),
                  onPressed: _copyAllBackupCodes,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Completion Button
          AppButton(
            text: "I've Saved My Codes — Finish",
            isFullWidth: true,
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
