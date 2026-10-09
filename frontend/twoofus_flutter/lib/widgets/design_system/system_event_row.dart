import 'package:flutter/material.dart';
import '../../theme/theme_controller.dart';

class SystemEventRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String text;
  final String? duration;
  final String time;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SystemEventRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.text,
    this.duration,
    required this.time,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;

    final color = iconColor ?? theme.textSecondary;

    return Center(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.textSecondary,
                  ),
                ),
              ),
              if (duration != null && duration!.isNotEmpty) ...[
                Text(
                  " • ",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: theme.textTertiary,
                  ),
                ),
                Text(
                  duration!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              Text(
                " • ",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: theme.textTertiary,
                ),
              ),
              Text(
                time,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: theme.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
