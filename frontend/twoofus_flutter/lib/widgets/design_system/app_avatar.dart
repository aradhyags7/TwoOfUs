import 'package:flutter/material.dart';
import '../../theme/theme_controller.dart';

class AppAvatar extends StatelessWidget {
  final double size;
  final String? name;
  final String? imageUrl;
  final bool isOnline;
  final bool showOnlineIndicator;
  final VoidCallback? onTap;

  const AppAvatar({
    super.key,
    this.size = 40.0,
    this.name,
    this.imageUrl,
    this.isOnline = false,
    this.showOnlineIndicator = false,
    this.onTap,
  });

  static const List<Color> _avatarHues = [
    Color(0xFF475569), // Slate
    Color(0xFF334155), // Dark Slate
    Color(0xFF3F3F46), // Zinc
    Color(0xFF4B5563), // Cool Grey
    Color(0xFF374151), // Deep Grey
    Color(0xFF365314), // Muted Olive
    Color(0xFF1E3A8A), // Muted Navy
    Color(0xFF701A75), // Muted Plum
    Color(0xFF134E4A), // Muted Teal
  ];

  Color _getHue(String seed) {
    if (seed.isEmpty) return _avatarHues.first;
    int hash = 0;
    for (int i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return _avatarHues[hash % _avatarHues.length];
  }

  String _getInitials(String? raw) {
    if (raw == null || raw.trim().isEmpty) return "?";
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return "${parts[0][0]}${parts[1][0]}".toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final initials = _getInitials(name);
    final fallbackColor = _getHue(name ?? "TwoOfUs");

    Widget avatarContent;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      avatarContent = Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallback(fallbackColor, initials),
      );
    } else {
      avatarContent = _buildFallback(fallbackColor, initials);
    }

    final double indicatorSize = (size * 0.28).clamp(8.0, 16.0);
    final double indicatorBorder = indicatorSize > 12 ? 2.5 : 2.0;

    Widget avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.border, width: 1),
          ),
          child: ClipOval(child: avatarContent),
        ),
        if (showOnlineIndicator)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: indicatorSize,
              height: indicatorSize,
              decoration: BoxDecoration(
                color: isOnline ? theme.success : theme.textTertiary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.bg, width: indicatorBorder),
              ),
            ),
          ),
      ],
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatar,
      );
    }

    return avatar;
  }

  Widget _buildFallback(Color bg, String initials) {
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: (size * 0.4).clamp(11.0, 36.0),
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
