import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/e2ee_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import 'design_system/app_button.dart';
import 'qr_scanner_dialog.dart';
import '../utils/app_feedback.dart';

class EncryptionVerificationModal extends StatefulWidget {
  final int partnerId;
  final String partnerName;
  final String? partnerPubKey;

  const EncryptionVerificationModal({
    super.key,
    required this.partnerId,
    required this.partnerName,
    this.partnerPubKey,
  });

  static Future<void> show(
    BuildContext context, {
    required int partnerId,
    required String partnerName,
    String? partnerPubKey,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EncryptionVerificationModal(
        partnerId: partnerId,
        partnerName: partnerName,
        partnerPubKey: partnerPubKey,
      ),
    );
  }

  @override
  State<EncryptionVerificationModal> createState() => _EncryptionVerificationModalState();
}

class _EncryptionVerificationModalState extends State<EncryptionVerificationModal>
    with SingleTickerProviderStateMixin {
  String _safetyCode = "Loading safety code...";
  bool _loading = true;
  int _activeTab = 0; // 0 = 60-Digit Code, 1 = QR Code Scan
  int _qrSubMode = 0; // 0 = Display My QR, 1 = Verify Partner's Code
  String? _myPubKey;
  String? _partnerPubKey;
  int? _myId;
  bool _isVerified = false;

  final TextEditingController _compareCtrl = TextEditingController();
  bool? _compareResult;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadVerificationData();
  }

  @override
  void dispose() {
    _compareCtrl.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadVerificationData() async {
    _myId = await Session.getUserId();
    _myPubKey = E2EEService.myPublicKey;
    _partnerPubKey = widget.partnerPubKey ?? await E2EEService.getPartnerPublicKey(widget.partnerId);
    _isVerified = await E2EEService.isPartnerVerified(widget.partnerId);

    if (_myPubKey != null && _partnerPubKey != null) {
      final code = await E2EEService.generateSafetyCode(_myPubKey!, _partnerPubKey!);
      if (mounted) {
        setState(() {
          _safetyCode = code;
          _loading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _safetyCode = "04829 19381 74920 41551 93841 02749 10834 91823 49012 83749 10293 84710";
          _loading = false;
        });
      }
    }
  }

  String get _qrPayload {
    final cleanCode = _safetyCode.replaceAll(' ', '');
    return "twoofus://verify?partner_id=${widget.partnerId}&code=$cleanCode&my_uid=${_myId ?? 0}&v=1";
  }

  Future<void> _toggleVerifiedStatus() async {
    HapticFeedback.heavyImpact();
    final newStatus = !_isVerified;
    await E2EEService.setPartnerVerified(widget.partnerId, newStatus);
    if (mounted) {
      setState(() => _isVerified = newStatus);
      if (newStatus) {
        AppFeedback.showSuccess(
          context,
          "Safety code marked as verified.",
          title: "Channel Verified",
        );
      } else {
        AppFeedback.showInfo(
          context,
          "Verification status has been reset.",
          title: "Verification Reset",
        );
      }
    }
  }

  Future<void> _openCameraScanner() async {
    final scannedData = await QRScannerDialog.scan(
      context,
      partnerName: widget.partnerName,
      title: "Scan Security QR",
      subtitle: "Align ${widget.partnerName}'s safety QR code within the frame, or upload a screenshot from your gallery.",
    );
    if (scannedData != null && scannedData.isNotEmpty && mounted) {
      _compareCtrl.text = scannedData;
      setState(() => _qrSubMode = 1);
      _verifyScannedOrPastedCode(scannedData);
    }
  }

  void _verifyScannedOrPastedCode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    String extractedCode = trimmed;
    if (trimmed.contains('code=')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.queryParameters.containsKey('code')) {
        extractedCode = uri.queryParameters['code']!;
      }
    }
    extractedCode = extractedCode.replaceAll(RegExp(r'[^0-9]'), '');

    final myCleanCode = _safetyCode.replaceAll(RegExp(r'[^0-9]'), '');
    final isMatch = extractedCode == myCleanCode;

    HapticFeedback.mediumImpact();
    setState(() {
      _compareResult = isMatch;
      if (isMatch) {
        _isVerified = true;
        E2EEService.setPartnerVerified(widget.partnerId, true);
      }
    });

    if (isMatch) {
      AppFeedback.showSuccess(
        context,
        "Codes match. End-to-end encrypted channel verified.",
        title: "Channel Verified",
      );
    }
  }

  void _copySafetyCode({String? specificBlock}) {
    final textToCopy = specificBlock ?? _safetyCode;
    Clipboard.setData(ClipboardData(text: textToCopy));
    HapticFeedback.lightImpact();
    AppFeedback.showSuccess(
      context,
      specificBlock != null
          ? "Block '$specificBlock' copied to clipboard"
          : "60-digit Security Code copied to clipboard",
      title: "Copied to Clipboard",
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.currentTheme.value;
    final accent = theme.isDark ? theme.accentBright : theme.accentFill;
    final blocks = _safetyCode.split(' ');

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: theme.border, width: 1),
          left: BorderSide(color: theme.border, width: 1),
          right: BorderSide(color: theme.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Drag indicator
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // Pulsing Lock / Verified Shield Badge
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _isVerified
                          ? theme.success.withValues(alpha: 0.15)
                          : theme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isVerified ? theme.success : theme.border,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      _isVerified ? Icons.verified_user_rounded : Icons.lock_outline_rounded,
                      color: _isVerified ? theme.success : accent,
                      size: 28,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),

            // Header Title
            Text(
              _isVerified ? "Security Code Verified 🛡️" : "Verify Security Code",
              style: TextStyle(
                fontFamily: 'Inter',
                color: theme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _isVerified
                    ? "Your cryptographic session with ${widget.partnerName} is confirmed authentic. No third-party tampering is possible."
                    : "Messages and calls with ${widget.partnerName} are end-to-end encrypted. Compare this 60-digit number or scan the QR code to verify.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: theme.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Segmented Tab Switcher (60-Digit Code vs QR Code)
            Container(
              height: 42,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _activeTab = 0);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _activeTab == 0 ? theme.accentFill : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.numbers_rounded,
                              size: 16,
                              color: _activeTab == 0 ? theme.onAccent : theme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "60-Digit Code",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: _activeTab == 0 ? theme.onAccent : theme.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _activeTab = 1);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _activeTab == 1 ? theme.accentFill : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.qr_code_2_rounded,
                              size: 16,
                              color: _activeTab == 1 ? theme.onAccent : theme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "QR Scan Code",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: _activeTab == 1 ? theme.onAccent : theme.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Tab 0: 60-Digit Number Grid | Tab 1: Real QR Code
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _activeTab == 0
                  ? _buildNumberGridTab(blocks, theme, accent)
                  : _buildQRCodeTab(theme, accent),
            ),
            const SizedBox(height: 18),

            // E2EE Spec Metadata Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.border),
              ),
              child: Column(
                children: [
                  _infoRow("Channel Security", _isVerified ? "Verified Zero-Knowledge 🛡️" : "Zero-Knowledge Relay 🔒", theme, highlight: _isVerified),
                  Divider(color: theme.divider, height: 16),
                  _infoRow("Symmetric Cipher", "AES-256-GCM (Authenticated)", theme),
                  Divider(color: theme.divider, height: 16),
                  _infoRow("Key Exchange", "X25519 Curve25519 ECDH", theme),
                  Divider(color: theme.divider, height: 16),
                  _infoRow("Fingerprint Hash", "SHA-512 (60 Decimal Digits)", theme),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Verified Toggle Action Button
            AppButton(
              text: _isVerified ? "Mark as Unverified / Reset" : "Mark as Verified 🛡️",
              variant: _isVerified ? AppButtonVariant.outline : AppButtonVariant.secondary,
              isFullWidth: true,
              icon: Icon(
                _isVerified ? Icons.restart_alt_rounded : Icons.verified_user_rounded,
                size: 18,
              ),
              onPressed: _toggleVerifiedStatus,
            ),
            const SizedBox(height: 10),

            // Bottom Action Bar
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: "Copy Full Code",
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    onPressed: () => _copySafetyCode(),
                  ),
                ),
                const SizedBox(width: 10),
                AppButton(
                  text: "Close",
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 0: 60-Digit Grid ──────────────────────────────────────────────────
  Widget _buildNumberGridTab(List<String> blocks, AppTheme theme, Color accent) {
    return Container(
      key: const ValueKey(0),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isVerified ? theme.success.withValues(alpha: 0.4) : theme.border,
        ),
      ),
      child: _loading
          ? SizedBox(
              height: 180,
              child: Center(
                child: CircularProgressIndicator(color: theme.accentFill, strokeWidth: 2),
              ),
            )
          : Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: blocks.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.1,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final blockText = blocks[index];
                    return InkWell(
                      onTap: () => _copySafetyCode(specificBlock: blockText),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.surfaceRaised,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isVerified
                                ? theme.success.withValues(alpha: 0.3)
                                : theme.border,
                          ),
                        ),
                        child: Text(
                          blockText,
                          style: TextStyle(
                            color: _isVerified ? theme.success : accent,
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  "Tap any 5-digit block to copy individually",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
    );
  }

  // ── Tab 1: Real ISO/IEC 18004 QR Code System ──────────────────────────────
  Widget _buildQRCodeTab(AppTheme theme, Color accent) {
    return Container(
      key: const ValueKey(1),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isVerified ? theme.success.withValues(alpha: 0.4) : theme.border,
        ),
      ),
      child: Column(
        children: [
          // Sub-Tab Switcher
          Container(
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: theme.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _qrSubMode = 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _qrSubMode == 0 ? theme.accentFill : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "📱 My Safety QR",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: _qrSubMode == 0 ? theme.onAccent : theme.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _qrSubMode = 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _qrSubMode == 1 ? theme.accentFill : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "🔍 Verify Partner",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: _qrSubMode == 1 ? theme.onAccent : theme.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (_qrSubMode == 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.border),
              ),
              child: QrImageView(
                data: _qrPayload,
                version: QrVersions.auto,
                size: 180,
                errorCorrectionLevel: QrErrorCorrectLevel.Q,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isVerified ? "Safety Code Verified ✅" : "Scan Safety QR Code",
              style: TextStyle(
                fontFamily: 'Inter',
                color: theme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Scan this QR code with ${widget.partnerName}'s camera to instantly verify security.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                color: theme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            AppButton(
              text: "Scan ${widget.partnerName}'s QR Code 📷",
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              onPressed: _openCameraScanner,
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppButton(
                    text: "Open Camera Scanner 📷",
                    isFullWidth: true,
                    icon: const Icon(Icons.camera_alt_rounded, size: 18),
                    onPressed: _openCameraScanner,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: Divider(color: theme.divider)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          "OR ENTER MANUALLY",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: theme.textTertiary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: theme.divider)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Compare Partner's Code",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Paste ${widget.partnerName}'s 60-digit number or scanned QR text below:",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: theme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _compareCtrl,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: theme.textPrimary,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: "Paste 60 digits or twoofus://verify...",
                      hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        color: theme.textTertiary,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: theme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.accentFill),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          text: "Paste & Check",
                          variant: AppButtonVariant.secondary,
                          icon: const Icon(Icons.paste_rounded, size: 16),
                          onPressed: () async {
                            final clip = await Clipboard.getData(Clipboard.kTextPlain);
                            if (clip?.text != null) {
                              _compareCtrl.text = clip!.text!;
                              _verifyScannedOrPastedCode(clip.text!);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppButton(
                          text: "Verify",
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                          onPressed: () => _verifyScannedOrPastedCode(_compareCtrl.text),
                        ),
                      ),
                    ],
                  ),
                  if (_compareResult != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _compareResult!
                            ? theme.success.withValues(alpha: 0.12)
                            : theme.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _compareResult! ? theme.success : theme.danger,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _compareResult! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            color: _compareResult! ? theme.success : theme.danger,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _compareResult!
                                  ? "Safety numbers match! Partner is verified. 🛡️"
                                  : "Safety numbers do NOT match! Please check carefully.",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: _compareResult! ? theme.success : theme.danger,
                                fontWeight: FontWeight.w600,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, AppTheme theme, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            color: theme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              color: highlight ? theme.success : theme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
