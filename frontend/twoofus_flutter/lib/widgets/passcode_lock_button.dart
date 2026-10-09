import 'package:flutter/material.dart';
import '../services/security_service.dart';
import '../theme/theme_controller.dart';


class PasscodeLockButton extends StatefulWidget {
  final double iconSize;
  final Color? color;

  const PasscodeLockButton({
    super.key,
    this.iconSize = 22,
    this.color,
  });

  @override
  State<PasscodeLockButton> createState() => _PasscodeLockButtonState();
}

class _PasscodeLockButtonState extends State<PasscodeLockButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    SecurityService.refreshPasscodeState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap() async {
    await _controller.forward();
    await _controller.reverse();
    if (mounted) {
      await SecurityService.lockApp(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SecurityService.passcodeNotifier,
      builder: (context, hasPasscode, child) {
        if (!hasPasscode) {
          return const SizedBox.shrink();
        }

        final color = widget.color ?? ThemeController.currentTheme.value.textSecondary;

        return ScaleTransition(
          scale: _scaleAnimation,
          child: IconButton(
            tooltip: "Lock App",
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            icon: Icon(
              Icons.lock_open_rounded,
              size: widget.iconSize,
              color: color,
            ),
            onPressed: _onTap,
          ),
        );
      },
    );
  }
}
