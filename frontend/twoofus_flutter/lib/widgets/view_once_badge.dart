import 'dart:math' as math;
import 'package:flutter/material.dart';

class ViewOnceBadge extends StatefulWidget {
  final bool isActive;
  final bool isOpened;
  final double size;
  final VoidCallback? onTap;

  const ViewOnceBadge({
    super.key,
    this.isActive = false,
    this.isOpened = false,
    this.size = 40.0,
    this.onTap,
  });

  @override
  State<ViewOnceBadge> createState() => _ViewOnceBadgeState();
}

class _ViewOnceBadgeState extends State<ViewOnceBadge> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const rose = Color(0xFFFF2D75);
    const violet = Color(0xFF9B51E0);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final isPulsing = widget.isActive && !widget.isOpened;

          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: isPulsing
                  ? [
                      BoxShadow(
                        color: rose.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: violet.withValues(alpha: 0.4),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: CustomPaint(
              painter: _ViewOnceDashedPainter(
                isActive: widget.isActive,
                isOpened: widget.isOpened,
                rotationAngle: isPulsing ? _animController.value * 2 * math.pi : 0.0,
                rose: rose,
                violet: violet,
              ),
              child: Center(
                child: Container(
                  width: widget.size * 0.72,
                  height: widget.size * 0.72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isPulsing
                        ? const LinearGradient(
                            colors: [rose, violet],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: widget.isOpened
                        ? Colors.white.withValues(alpha: 0.12)
                        : (!widget.isActive ? Colors.white.withValues(alpha: 0.08) : null),
                  ),
                  child: Center(
                    child: Text(
                      "1",
                      style: TextStyle(
                        color: widget.isOpened
                            ? Colors.white54
                            : (widget.isActive ? Colors.white : Colors.white70),
                        fontSize: widget.size * 0.42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ViewOnceDashedPainter extends CustomPainter {
  final bool isActive;
  final bool isOpened;
  final double rotationAngle;
  final Color rose;
  final Color violet;

  _ViewOnceDashedPainter({
    required this.isActive,
    required this.isOpened,
    required this.rotationAngle,
    required this.rose,
    required this.violet,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isActive ? 2.0 : 1.5
      ..strokeCap = StrokeCap.round;

    if (isOpened) {
      paint.color = Colors.white30;
    } else if (isActive) {
      paint.shader = SweepGradient(
        colors: [rose, violet, rose],
        transform: GradientRotation(rotationAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    } else {
      paint.color = Colors.white54;
    }

    // Draw WhatsApp-style 6-segmented dashed ring
    const totalSegments = 6;
    const gapAngle = (math.pi * 2) / (totalSegments * 4); // gap fraction
    const sweepAngle = ((math.pi * 2) / totalSegments) - gapAngle;

    for (int i = 0; i < totalSegments; i++) {
      final startAngle = rotationAngle + (i * ((math.pi * 2) / totalSegments)) + (gapAngle / 2);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ViewOnceDashedPainter oldDelegate) {
    return oldDelegate.isActive != isActive ||
        oldDelegate.isOpened != isOpened ||
        oldDelegate.rotationAngle != rotationAngle;
  }
}
