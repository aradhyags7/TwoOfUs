import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_service.dart';
import '../theme/theme_controller.dart';

class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  Color get bg => ThemeController.currentTheme.value.surfaceTeal;
  Color get surfaceCard => ThemeController.currentTheme.value.surface;
  Color get rose => ThemeController.currentTheme.value.primary;
  Color get violet => ThemeController.currentTheme.value.secondary;

  bool _isLoading = true;
  String? _errorMessage;
  String? _secret;
  String? _otpauthUrl;
  String? _userEmail;
  List<String> _backupCodes = [];

  // Selected setup method: 0 = Google Authenticator (TOTP), 1 = Email OTP
  int _selectedMethod = 0;

  // Step: 0 = Method Setup & OTP confirmation, 1 = Backup codes display
  int _currentStep = 0;
  final TextEditingController _codeController = TextEditingController();
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
    _fetchSetupDetails();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
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
      final fallback = res["fallback_code"]?.toString();
      if (fallback != null && fallback.isNotEmpty) {
        _codeController.text = fallback;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("📬 Code [$fallback] loaded automatically!"),
            backgroundColor: const Color(0xFF200F35),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("6-digit code sent to ${_userEmail ?? 'your email'}! 📬"),
            backgroundColor: const Color(0xFF200F35),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res?["error"] ?? "Failed to send email verification code."),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _submitVerification() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Please enter the complete 6-digit code"),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
        ),
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
        _currentStep = 1; // Show backup recovery codes
      });
    } else {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res?["error"] ?? "Invalid verification code. Try again."),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copySecret() {
    if (_secret == null) return;
    Clipboard.setData(ClipboardData(text: _secret!));
    HapticFeedback.selectionClick();
    setState(() => _copiedSecret = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Secret key copied to clipboard!"),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copiedSecret = false);
    });
  }

  void _copyAllBackupCodes() {
    if (_backupCodes.isEmpty) return;
    final all = _backupCodes.join("\n");
    Clipboard.setData(ClipboardData(text: all));
    HapticFeedback.selectionClick();
    setState(() => _copiedBackupCodes = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All 8 backup recovery codes copied! Keep them secure."),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context, _currentStep == 1),
        ),
        title: const Text(
          "Two-Factor Authentication",
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                        Text(_errorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _fetchSetupDetails,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text("Retry"),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Method Segmented Selector
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
                    icon: Icons.mail_outline_rounded,
                    label: "Email OTP",
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_selectedMethod == 0) ...[
            _buildAuthenticatorAppSection(),
          ] else ...[
            _buildEmailOtpSection(),
          ],

          const SizedBox(height: 24),

          // Common Verification Code Input
          Text(
            _selectedMethod == 0
                ? "ENTER 6-DIGIT CODE FROM AUTHENTICATOR:"
                : "ENTER 6-DIGIT CODE SENT TO EMAIL:",
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 10,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: "123456",
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), letterSpacing: 10),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: rose, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: rose,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
              ],
            ),
          ),
          const SizedBox(height: 30),
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
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? rose : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.white60, size: 18),
            const SizedBox(width: 8),
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

  Widget _buildAuthenticatorAppSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // QR Code Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              const Text(
                "Scan with Google Authenticator",
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                "Open Google Authenticator, Authy, or Microsoft Authenticator and scan this QR code:",
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Rendered QR Code
              if (_otpauthUrl != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _otpauthUrl!,
                    version: QrVersions.auto,
                    size: 175,
                    backgroundColor: Colors.white,
                  ),
                ),
              const SizedBox(height: 16),

              // Manual Entry Secret Key Box
              const Text(
                "OR ENTER KEY MANUALLY:",
                style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _secret ?? "",
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _copySecret,
                      icon: Icon(_copiedSecret ? Icons.check_circle_rounded : Icons.copy_rounded,
                          color: _copiedSecret ? Colors.greenAccent : Colors.white70, size: 18),
                      tooltip: "Copy Key",
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmailOtpSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                      "Email Verification (OTP)",
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userEmail ?? "Registered Email",
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "Every time you log in from a new device, a 6-digit security code will be dispatched to your registered email.",
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_emailCooldownSeconds > 0 || _isSendingEmail) ? null : _sendEmailOtp,
              icon: _isSendingEmail
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                    )
                  : const Icon(Icons.send_rounded, size: 16, color: Colors.amberAccent),
              label: Text(
                _emailCooldownSeconds > 0
                    ? "Resend Code in ${_emailCooldownSeconds}s"
                    : "Send 6-Digit Code to Email",
                style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.amberAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCodesStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedMethod == 0
                            ? "Google Authenticator Enabled!"
                            : "Email 2FA Enabled!",
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Your account is now protected with Two-Factor Authentication.",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Recovery Codes Warning
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Save these 8 one-time backup recovery codes in a safe place. If you lose access to your Authenticator app or email, each code can be used once to log in.",
                    style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Grid of 8 Codes
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceCard,
              borderRadius: BorderRadius.circular(16),
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
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        _backupCodes[index],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 1.2,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _copyAllBackupCodes,
                    icon: Icon(_copiedBackupCodes ? Icons.check_circle_rounded : Icons.copy_all_rounded,
                        color: _copiedBackupCodes ? Colors.greenAccent : Colors.pinkAccent, size: 18),
                    label: Text(
                      _copiedBackupCodes ? "Backup Codes Copied!" : "Copy All 8 Codes",
                      style: TextStyle(
                        color: _copiedBackupCodes ? Colors.greenAccent : Colors.pinkAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _copiedBackupCodes ? Colors.greenAccent : Colors.pinkAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Done Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: rose,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text(
                "I've Saved My Codes — Done",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
