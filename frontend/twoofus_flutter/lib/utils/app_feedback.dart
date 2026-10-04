import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum FeedbackType { error, success, info }

/// Premium, unified feedback notification banners for TwoOfUs.
/// Eliminates plain, unstyled SnackBars and inappropriate emoji clutter.
class AppFeedback {
  AppFeedback._();

  static void showError(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) {
    HapticFeedback.mediumImpact();
    _show(
      context,
      message: message,
      title: title ?? "Error",
      type: FeedbackType.error,
      duration: duration,
    );
  }

  static void showSuccess(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    HapticFeedback.lightImpact();
    _show(
      context,
      message: message,
      title: title,
      type: FeedbackType.success,
      duration: duration,
    );
  }

  static void showInfo(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    HapticFeedback.selectionClick();
    _show(
      context,
      message: message,
      title: title,
      type: FeedbackType.info,
      duration: duration,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    String? title,
    required FeedbackType type,
    required Duration duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    Color accentColor;
    Color bgSurface;
    IconData iconData;

    switch (type) {
      case FeedbackType.error:
        accentColor = const Color(0xFFFF4D4D);
        bgSurface = const Color(0xFF1E1015);
        iconData = Icons.error_outline_rounded;
        break;
      case FeedbackType.success:
        accentColor = const Color(0xFF00E676);
        bgSurface = const Color(0xFF0E1A14);
        iconData = Icons.check_circle_outline_rounded;
        break;
      case FeedbackType.info:
        accentColor = const Color(0xFF9D65FF);
        bgSurface = const Color(0xFF141024);
        iconData = Icons.info_outline_rounded;
        break;
    }

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: duration,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bgSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.15),
                blurRadius: 18,
                offset: const Offset(0, 6),
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.28),
                    width: 1,
                  ),
                ),
                child: Icon(
                  iconData,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null && title.isNotEmpty) ...[
                      Text(
                        title,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => messenger.hideCurrentSnackBar(),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.4),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
