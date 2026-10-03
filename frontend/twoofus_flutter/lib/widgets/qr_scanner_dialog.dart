import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerDialog extends StatefulWidget {
  final String partnerName;
  final String title;
  final String? subtitle;

  const QRScannerDialog({
    super.key,
    required this.partnerName,
    this.title = "Scan QR Code",
    this.subtitle,
  });

  static Future<String?> scan(
    BuildContext context, {
    required String partnerName,
    String title = "Scan QR Code",
    String? subtitle,
  }) {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerDialog(
          partnerName: partnerName,
          title: title,
          subtitle: subtitle,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<QRScannerDialog> createState() => _QRScannerDialogState();
}

class _QRScannerDialogState extends State<QRScannerDialog>
    with SingleTickerProviderStateMixin {
  late MobileScannerController _controller;
  late AnimationController _laserAnimCtrl;
  late Animation<double> _laserAnim;
  bool _hasScanned = false;
  bool _isTorchOn = false;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _laserAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _laserAnim = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _laserAnimCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _laserAnimCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _hasScanned = true;
        HapticFeedback.heavyImpact();
        Navigator.pop(context, value.trim());
        break;
      }
    }
  }

  Future<void> _pickAndAnalyzeFromGallery() async {
    if (_isAnalyzing) return;
    setState(() => _isAnalyzing = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        setState(() => _isAnalyzing = false);
        return;
      }

      final barcodes = await _controller.analyzeImage(picked.path);
      if (barcodes != null && barcodes.barcodes.isNotEmpty) {
        final val = barcodes.barcodes.first.rawValue;
        if (val != null && val.trim().isNotEmpty) {
          _hasScanned = true;
          HapticFeedback.heavyImpact();
          if (mounted) Navigator.pop(context, val.trim());
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("No QR code detected in the selected image. Please try another."),
            backgroundColor: const Color(0xFF4A0E17),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error reading image: $e"),
            backgroundColor: const Color(0xFF4A0E17),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanWindowSize = MediaQuery.of(context).size.width * 0.72;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Viewfinder
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // 2. Dark Overlay with Viewfinder Hole
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.65),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: scanWindowSize,
                    height: scanWindowSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Viewfinder Reticle Frame with Animated Scanner Laser
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: scanWindowSize,
              height: scanWindowSize,
              child: Stack(
                children: [
                  // Corner brackets
                  CustomPaint(
                    size: Size(scanWindowSize, scanWindowSize),
                    painter: _ReticleCornerPainter(),
                  ),

                  // Animated Neon Laser Line
                  AnimatedBuilder(
                    animation: _laserAnim,
                    builder: (context, child) {
                      return Positioned(
                        top: scanWindowSize * _laserAnim.value,
                        left: 12,
                        right: 12,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: const LinearGradient(
                              colors: [
                                Colors.transparent,
                                Color(0xFFFF2A6D),
                                Color(0xFF00E676),
                                Color(0xFFFF2A6D),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF2A6D).withValues(alpha: 0.8),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 4. Top Header & Controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close Button
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),

                  // Title Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFFF2A6D), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Actions: Gallery & Torch
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          icon: _isAnalyzing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.photo_library_rounded, color: Colors.white, size: 20),
                          tooltip: "Upload from Gallery",
                          onPressed: _pickAndAnalyzeFromGallery,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: _isTorchOn ? const Color(0xFFFF2A6D) : Colors.black54,
                        child: IconButton(
                          icon: Icon(
                            _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () async {
                            await _controller.toggleTorch();
                            setState(() => _isTorchOn = !_isTorchOn);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 5. Bottom Instructions Card
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161324).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle ??
                          "Point camera at your partner's QR code on their screen, or upload a saved QR screenshot.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickAndAnalyzeFromGallery,
                      icon: const Icon(Icons.image_search_rounded, size: 18, color: Colors.white),
                      label: Text(
                        _isAnalyzing ? "Reading image..." : "Upload QR from Gallery",
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReticleCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cornerLength = 26.0;
    const strokeWidth = 3.5;
    const radius = 18.0;

    final paint = Paint()
      ..color = const Color(0xFFFF2A6D)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // Top-Left Corner
    path.moveTo(0, cornerLength);
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.lineTo(cornerLength, 0);

    // Top-Right Corner
    path.moveTo(size.width - cornerLength, 0);
    path.lineTo(size.width - radius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, radius);
    path.lineTo(size.width, cornerLength);

    // Bottom-Right Corner
    path.moveTo(size.width, size.height - cornerLength);
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(size.width, size.height, size.width - radius, size.height);
    path.lineTo(size.width - cornerLength, size.height);

    // Bottom-Left Corner
    path.moveTo(cornerLength, size.height);
    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.lineTo(0, size.height - cornerLength);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
