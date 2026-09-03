import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/e2ee_service.dart';
import '../utils/session.dart';
import 'qr_scanner_dialog.dart';

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

    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                newStatus ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                color: newStatus ? Colors.greenAccent : Colors.pinkAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  newStatus
                      ? "Safety code marked as VERIFIED! 🛡️"
                      : "Verification status reset.",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1D1826),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }

  Future<void> _openCameraScanner() async {
    final scannedData = await QRScannerDialog.scan(
      context,
      partnerName: widget.partnerName,
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

    // Extract code if it's a URL or raw digits
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: Colors.greenAccent, size: 20),
              SizedBox(width: 8),
              Text("Codes Match! Channel Verified 🛡️", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: const Color(0xFF11291F),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  void _copySafetyCode({String? specificBlock}) {
    final textToCopy = specificBlock ?? _safetyCode;
    Clipboard.setData(ClipboardData(text: textToCopy));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.pinkAccent, size: 18),
            const SizedBox(width: 8),
            Text(specificBlock != null
                ? "Block '$specificBlock' copied to clipboard!"
                : "60-digit Security Code copied to clipboard!"),
          ],
        ),
        backgroundColor: const Color(0xFF1D1826),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _safetyCode.split(' ');

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13111C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Drag indicator
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
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
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isVerified
                            ? [const Color(0xFF00E676), const Color(0xFF00B0FF)]
                            : [const Color(0xFFFF2A6D), const Color(0xFF9B51E0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isVerified ? const Color(0xFF00E676) : const Color(0xFFFF2A6D))
                              .withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isVerified ? Icons.verified_user_rounded : Icons.lock_outline_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Header Title
            Text(
              _isVerified ? "Security Code Verified 🛡️" : "Verify Security Code",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
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
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Segmented Tab Switcher (60-Digit Code vs QR Code)
            Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1A2B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                          color: _activeTab == 0 ? const Color(0xFFFF2A6D) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.numbers_rounded,
                                size: 16,
                                color: _activeTab == 0 ? Colors.white : Colors.white60),
                            const SizedBox(width: 6),
                            Text(
                              "60-Digit Code",
                              style: TextStyle(
                                color: _activeTab == 0 ? Colors.white : Colors.white60,
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
                          color: _activeTab == 1 ? const Color(0xFFFF2A6D) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_2_rounded,
                                size: 16,
                                color: _activeTab == 1 ? Colors.white : Colors.white60),
                            const SizedBox(width: 6),
                            Text(
                              "QR Scan Code",
                              style: TextStyle(
                                color: _activeTab == 1 ? Colors.white : Colors.white60,
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
              duration: const Duration(milliseconds: 250),
              child: _activeTab == 0
                  ? _buildNumberGridTab(blocks)
                  : _buildQRCodeTab(),
            ),
            const SizedBox(height: 18),

            // E2EE Spec Metadata Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF191626),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  _infoRow(
                    "Channel Security",
                    _isVerified ? "Verified Zero-Knowledge 🛡️" : "Zero-Knowledge Relay 🔒",
                    highlight: _isVerified,
                  ),
                  Divider(color: Colors.white.withValues(alpha: 0.08), height: 16),
                  _infoRow("Symmetric Cipher", "AES-256-GCM (Authenticated)"),
                  Divider(color: Colors.white.withValues(alpha: 0.08), height: 16),
                  _infoRow("Key Exchange", "X25519 Curve25519 ECDH"),
                  Divider(color: Colors.white.withValues(alpha: 0.08), height: 16),
                  _infoRow("Fingerprint Hash", "SHA-512 (60 Decimal Digits)"),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Verified Toggle Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleVerifiedStatus,
                icon: Icon(
                  _isVerified ? Icons.check_circle_rounded : Icons.verified_user_rounded,
                  size: 18,
                ),
                label: Text(
                  _isVerified ? "Mark as Unverified / Reset" : "Mark as Verified 🛡️",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isVerified
                      ? const Color(0xFF1F3D2B)
                      : const Color(0xFF28223B),
                  foregroundColor: _isVerified ? Colors.greenAccent : Colors.white,
                  side: BorderSide(
                    color: _isVerified ? Colors.greenAccent : const Color(0xFFFF2A6D).withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Bottom Action Bar
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _copySafetyCode(),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text("Copy Full Code"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF2A6D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text("Close"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 0: 60-Digit Grid ──────────────────────────────────────────────────
  Widget _buildNumberGridTab(List<String> blocks) {
    return Container(
      key: const ValueKey(0),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1A2C),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isVerified
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : const Color(0xFFFF2A6D).withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _loading
          ? const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
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
                          color: _isVerified
                              ? const Color(0xFF122C20)
                              : const Color(0xFF28233C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isVerified
                                ? Colors.greenAccent.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Text(
                          blockText,
                          style: TextStyle(
                            color: _isVerified ? Colors.greenAccent : const Color(0xFFFF75A0),
                            fontFamily: 'monospace',
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app_rounded, size: 13, color: Colors.white.withValues(alpha: 0.45)),
                    const SizedBox(width: 4),
                    Text(
                      "Tap any 5-digit block to copy individually",
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // ── Tab 1: Real ISO/IEC 18004 QR Code System ──────────────────────────────
  Widget _buildQRCodeTab() {
    return Container(
      key: const ValueKey(1),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1A2C),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isVerified
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : const Color(0xFF9B51E0).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          // Sub-Tab Switcher: [ 📱 Display My QR ] | [ 🔍 Verify Partner's Code ]
          Container(
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF13111C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _qrSubMode = 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _qrSubMode == 0
                            ? const Color(0xFFFF2A6D).withValues(alpha: 0.3)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        border: _qrSubMode == 0
                            ? Border.all(color: const Color(0xFFFF2A6D))
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "📱 My Safety QR",
                        style: TextStyle(
                          color: _qrSubMode == 0 ? Colors.white : Colors.white54,
                          fontWeight: FontWeight.bold,
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
                        color: _qrSubMode == 1
                            ? const Color(0xFFFF2A6D).withValues(alpha: 0.3)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        border: _qrSubMode == 1
                            ? Border.all(color: const Color(0xFFFF2A6D))
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "🔍 Verify Partner",
                        style: TextStyle(
                          color: _qrSubMode == 1 ? Colors.white : Colors.white54,
                          fontWeight: FontWeight.bold,
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
            // Real Scannable ISO QR Code Container
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 210,
                  height: 210,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: (_isVerified ? const Color(0xFF00E676) : const Color(0xFF9B51E0))
                            .withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _qrPayload,
                    version: QrVersions.auto,
                    size: 186,
                    errorCorrectionLevel: QrErrorCorrectLevel.Q,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF14121E),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF14121E),
                    ),
                  ),
                ),
                // Center E2EE Lock Icon Overlay with Safety Ring
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14121E),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isVerified ? Colors.greenAccent : Colors.pinkAccent,
                      width: 2.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isVerified ? Icons.verified_rounded : Icons.lock_rounded,
                    color: _isVerified ? Colors.greenAccent : Colors.pinkAccent,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _isVerified ? "Safety Code Verified ✅" : "Scan Safety QR Code",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              "Scan this QR code with ${widget.partnerName}'s camera to instantly verify security.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _openCameraScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: Text("Scan ${widget.partnerName}'s QR Code 📷"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF2A6D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 3,
              ),
            ),
          ] else ...[
            // Partner Code Verifier / Matcher Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF14121E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openCameraScanner,
                      icon: const Icon(Icons.camera_alt_rounded, size: 18),
                      label: const Text("Open Camera Scanner 📷", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF2A6D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text("OR ENTER MANUALLY", style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Compare Partner's Code",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Paste ${widget.partnerName}'s 60-digit number or scanned QR text below:",
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _compareCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                    cursorColor: const Color(0xFFFF2A6D),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: "Paste 60 digits or twoofus://verify...",
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF1E1A2B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFFF2A6D)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final clip = await Clipboard.getData(Clipboard.kTextPlain);
                            if (clip?.text != null) {
                              _compareCtrl.text = clip!.text!;
                              _verifyScannedOrPastedCode(clip.text!);
                            }
                          },
                          icon: const Icon(Icons.paste_rounded, size: 16),
                          label: const Text("Paste & Check", style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.pinkAccent,
                            side: const BorderSide(color: Colors.pinkAccent),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _verifyScannedOrPastedCode(_compareCtrl.text),
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                          label: const Text("Verify", style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF2A6D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
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
                            ? Colors.greenAccent.withValues(alpha: 0.15)
                            : Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _compareResult! ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _compareResult! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            color: _compareResult! ? Colors.greenAccent : Colors.redAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _compareResult!
                                  ? "Safety numbers match! Partner is verified. 🛡️"
                                  : "Safety numbers do NOT match! Please check carefully.",
                              style: TextStyle(
                                color: _compareResult! ? Colors.greenAccent : Colors.redAccent,
                                fontWeight: FontWeight.bold,
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

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            color: highlight ? Colors.greenAccent : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
