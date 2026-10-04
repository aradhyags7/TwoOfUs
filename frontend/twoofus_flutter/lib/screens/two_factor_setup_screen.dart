import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_service.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — Two-Factor Authentication Setup (Apple / 1Password / Telegram Style)
// ─────────────────────────────────────────────────────────────────────────────

class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  Color get bg => ThemeController.currentTheme.value.bg;
  Color get surfaceCard => ThemeController.currentTheme.value.surface;
  Color get surfaceElevated => ThemeController.currentTheme.value.surfaceElevated;
  Color get rose => ThemeController.currentTheme.value.primary;
  Color get violet => ThemeController.currentTheme.value.secondary;

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
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                onPressed: () => Navigator.pop(context, _currentStep == 1),
              ),
            ),
          ),
        ),
        title: const Text(
          "Two-Factor Security",
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: rose))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _fetchSetupDetails,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text("Retry Setup"),
                          style: ElevatedButton.styleFrom(backgroundColor: rose, foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                  ),
                )
              : _currentStep == 0
                  ? _buildSetupStep()
                  : _buildBackupCodesStep(),
    );
  }

  Widget _buildSetupStep() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Step 1 of 2 Indicator ──────────────────────────────────────────
          _buildProgressPill(step: 1, total: 2, label: "Verification Setup"),
          const SizedBox(height: 16),

          // ── Hero Icon & Title ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [rose.withValues(alpha: 0.2), violet.withValues(alpha: 0.15)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: rose.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.shield_rounded, color: rose, size: 36),
          ),
          const SizedBox(height: 14),
          const Text(
            "Protect Your Couple Space",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Add a layer of defense against unauthorized logins using an authenticator app or email verification.",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // ── Segmented Method Selector ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _methodTab(
                    index: 0,
                    icon: Icons.qr_code_scanner_rounded,
                    label: "Authenticator App",
                  ),
                ),
                Expanded(
                  child: _methodTab(
                    index: 1,
                    icon: Icons.alternate_email_rounded,
                    label: "Email OTP",
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // ── Active Method Card ─────────────────────────────────────────────
          if (_selectedMethod == 0)
            _buildAuthenticatorAppCard()
          else
            _buildEmailOtpCard(),

          const SizedBox(height: 24),

          // ── 6-Box PIN Code Input ───────────────────────────────────────────
          _buildPinInputSection(),

          const SizedBox(height: 24),

          // ── Verify & Activate Button ───────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_isSubmitting || _codeController.text.trim().length != 6)
                  ? null
                  : _submitVerification,
              style: ElevatedButton.styleFrom(
                backgroundColor: rose,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                disabledForegroundColor: Colors.white30,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _selectedMethod == 0 ? "Verify & Enable Authenticator" : "Verify & Enable Email 2FA",
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildProgressPill({required int step, required int total, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: rose.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "STEP $step OF $total",
              style: TextStyle(color: rose, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _methodTab({
    required int index,
    required IconData icon,
    required String label,
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? rose : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: rose.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.white60, size: 17),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthenticatorAppCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Step 1: Scan QR Code
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: rose.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text("1", style: TextStyle(color: rose, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Scan QR Code with Authenticator",
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Compatible with Google Authenticator, Microsoft Authenticator, Apple Passwords, or 1Password.",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 18),

          // Rendered QR Code
          if (_otpauthUrl != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: _otpauthUrl!,
                version: QrVersions.auto,
                size: 170,
                backgroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 20),

          // Step 2: Manual Key Fallback
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: violet.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text("2", style: TextStyle(color: violet, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Can't scan? Copy setup key manually",
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _secret ?? "••••••••••••",
                    style: TextStyle(
                      color: rose,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
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
                          ? Colors.greenAccent.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copiedSecret ? Icons.check_circle_rounded : Icons.copy_rounded,
                          color: _copiedSecret ? Colors.greenAccent : Colors.white70,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _copiedSecret ? "Copied" : "Copy",
                          style: TextStyle(
                            color: _copiedSecret ? Colors.greenAccent : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
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

  Widget _buildEmailOtpCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_read_rounded, color: Colors.blueAccent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Email Verification Code",
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userEmail ?? "Your registered email",
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "When enabled, signing in from any new device will require a 6-digit code delivered to your registered email.",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: (_emailCooldownSeconds > 0 || _isSendingEmail) ? null : _sendEmailOtp,
              icon: _isSendingEmail
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: rose),
                    )
                  : Icon(Icons.send_rounded, size: 16, color: rose),
              label: Text(
                _emailCooldownSeconds > 0
                    ? "Resend Code in ${_emailCooldownSeconds}s"
                    : "Send 6-Digit Code to Email",
                style: TextStyle(color: rose, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: rose.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 6-Box PIN Code View ────────────────────────────────────────────────────
  Widget _buildPinInputSection() {
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
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ),

        // Stacked Custom 6-Box Digit View with hidden TextField
        GestureDetector(
          onTap: () => _codeFocusNode.requestFocus(),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surfaceCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _codeFocusNode.hasFocus
                    ? rose.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
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
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFocusedBox
                              ? rose
                              : isFilled
                                  ? rose.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.1),
                          width: isFocusedBox ? 2 : 1,
                        ),
                        boxShadow: isFocusedBox
                            ? [
                                BoxShadow(
                                  color: rose.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        char,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
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

  // ── Step 2: Backup Recovery Codes ──────────────────────────────────────────
  Widget _buildBackupCodesStep() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProgressPill(step: 2, total: 2, label: "Save Emergency Codes"),
          const SizedBox(height: 18),

          // Success Hero Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.greenAccent.withValues(alpha: 0.15),
                  Colors.tealAccent.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
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
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Your account is now guarded by two-factor authentication.",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Recovery Codes Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_reset_rounded, color: Colors.amberAccent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Emergency Recovery Codes",
                        style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Each single-use code can be used to log in if you lose phone or email access. Store them safely in a password manager.",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Codes Grid Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                        color: bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${(index + 1).toString().padLeft(2, '0')}. ",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _backupCodes[index],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
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
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _copyAllBackupCodes,
                    icon: Icon(
                      _copiedBackupCodes ? Icons.check_circle_rounded : Icons.copy_all_rounded,
                      color: _copiedBackupCodes ? Colors.greenAccent : rose,
                      size: 18,
                    ),
                    label: Text(
                      _copiedBackupCodes ? "Recovery Codes Copied!" : "Copy All 8 Codes",
                      style: TextStyle(
                        color: _copiedBackupCodes ? Colors.greenAccent : rose,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _copiedBackupCodes ? Colors.greenAccent : rose.withValues(alpha: 0.6),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Completion Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: rose,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text(
                "I've Saved My Codes — Finish",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
