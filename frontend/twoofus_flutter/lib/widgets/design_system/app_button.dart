import 'package:flutter/material.dart';
import '../../theme/theme_controller.dart';

enum AppButtonVariant {
  primary,
  secondary,
  outline,
  ghost,
  danger,
}

enum AppButtonSize {
  regular, // 48px
  compact, // 40px
  small,   // 32px
}

class AppButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final Widget? icon;
  final bool isLoading;
  final bool isFullWidth;
  final double? width;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.regular,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.width,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _isPressed = false;

  double get _height {
    switch (widget.size) {
      case AppButtonSize.regular:
        return 48.0;
      case AppButtonSize.compact:
        return 40.0;
      case AppButtonSize.small:
        return 32.0;
    }
  }

  double get _fontSize {
    switch (widget.size) {
      case AppButtonSize.regular:
        return 15.0;
      case AppButtonSize.compact:
        return 14.0;
      case AppButtonSize.small:
        return 13.0;
    }
  }

  EdgeInsets get _padding {
    switch (widget.size) {
      case AppButtonSize.regular:
        return const EdgeInsets.symmetric(horizontal: 20.0);
      case AppButtonSize.compact:
        return const EdgeInsets.symmetric(horizontal: 16.0);
      case AppButtonSize.small:
        return const EdgeInsets.symmetric(horizontal: 12.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isEnabled = widget.onPressed != null && !widget.isLoading;

    Color bg;
    Color fg;
    Border? border;

    switch (widget.variant) {
      case AppButtonVariant.primary:
        bg = isEnabled ? theme.accentFill : theme.accentFill.withValues(alpha: 0.4);
        fg = theme.onAccent;
        border = theme.isDark ? Border.all(color: theme.accentBorder, width: 1) : null;
        break;
      case AppButtonVariant.secondary:
        bg = isEnabled ? theme.surfaceRaised : theme.surfaceRaised.withValues(alpha: 0.4);
        fg = isEnabled ? theme.textPrimary : theme.textTertiary;
        border = Border.all(color: theme.border, width: 1);
        break;
      case AppButtonVariant.outline:
        bg = Colors.transparent;
        fg = isEnabled ? theme.textPrimary : theme.textTertiary;
        border = Border.all(color: theme.border, width: 1);
        break;
      case AppButtonVariant.ghost:
        bg = Colors.transparent;
        fg = isEnabled
            ? (theme.isDark ? theme.accentBright : theme.accentFill)
            : theme.textTertiary;
        break;
      case AppButtonVariant.danger:
        bg = isEnabled ? theme.danger : theme.danger.withValues(alpha: 0.4);
        fg = Colors.white;
        break;
    }

    Widget content;
    if (widget.isLoading) {
      content = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(fg),
        ),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            IconTheme(
              data: IconThemeData(color: fg, size: _fontSize + 3),
              child: widget.icon!,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            widget.text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: _fontSize,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: -0.1,
            ),
          ),
        ],
      );
    }

    Widget button = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: _height,
      width: widget.isFullWidth ? double.infinity : widget.width,
      padding: _padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: border,
      ),
      alignment: Alignment.center,
      child: content,
    );

    return GestureDetector(
      onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
      onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
      onTap: isEnabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: button,
      ),
    );
  }
}
