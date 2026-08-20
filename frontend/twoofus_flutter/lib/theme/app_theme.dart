import 'package:flutter/material.dart';

class AppTheme {
  final String id;
  final String name;
  final String subtitle;

  final Color bg;
  final Color surface;
  final Color surfaceTeal;
  final Color primary;
  final Color secondary;
  final Color gradientStart;
  final Color gradientEnd;
  final Color textPrimary;
  final Color textMuted;
  final Color border;
  final Color glow;
  final Color bubbleSelf;
  final Color bubblePartner;

  const AppTheme({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.bg,
    required this.surface,
    required this.surfaceTeal,
    required this.primary,
    required this.secondary,
    required this.gradientStart,
    required this.gradientEnd,
    required this.textPrimary,
    required this.textMuted,
    required this.border,
    required this.glow,
    required this.bubbleSelf,
    required this.bubblePartner,
  });

  static const AppTheme defaultTheme = AppTheme(
    id: 'default',
    name: 'TwoOfUs',
    subtitle: 'The classic TwoOfUs experience',
    bg: Color(0xFF0D1117),
    surface: Color(0xFF1E1B2E),
    surfaceTeal: Color(0xFF132F38),
    primary: Color(0xFFFF6B9D),
    secondary: Color(0xFF7C3AED),
    gradientStart: Color(0xFFFF6B9D),
    gradientEnd: Color(0xFF7C3AED),
    textPrimary: Colors.white,
    textMuted: Color(0x99FFFFFF),
    border: Color(0x1AFFFFFF),
    glow: Color(0x33FF6B9D),
    bubbleSelf: Color(0xFF7C3AED),
    bubblePartner: Color(0xFF1E1B2E),
  );

  static const AppTheme midnightTheme = AppTheme(
    id: 'midnight',
    name: 'Midnight',
    subtitle: 'Deep, calm and private',
    bg: Color(0xFF070A0F),
    surface: Color(0xFF121722),
    surfaceTeal: Color(0xFF0F1D2A),
    primary: Color(0xFF3B82F6),
    secondary: Color(0xFF8B5CF6),
    gradientStart: Color(0xFF3B82F6),
    gradientEnd: Color(0xFF8B5CF6),
    textPrimary: Colors.white,
    textMuted: Color(0x99FFFFFF),
    border: Color(0x203B82F6),
    glow: Color(0x333B82F6),
    bubbleSelf: Color(0xFF2563EB),
    bubblePartner: Color(0xFF121722),
  );

  static const AppTheme roseTheme = AppTheme(
    id: 'rose',
    name: 'Rose',
    subtitle: 'Warm and romantic',
    bg: Color(0xFF12080D),
    surface: Color(0xFF24101A),
    surfaceTeal: Color(0xFF1A1F29),
    primary: Color(0xFFFF4D8D),
    secondary: Color(0xFF9333EA),
    gradientStart: Color(0xFFFF4D8D),
    gradientEnd: Color(0xFF9333EA),
    textPrimary: Colors.white,
    textMuted: Color(0x99FFFFFF),
    border: Color(0x24FF4D8D),
    glow: Color(0x33FF4D8D),
    bubbleSelf: Color(0xFFE11D48),
    bubblePartner: Color(0xFF24101A),
  );

  static const AppTheme oceanTheme = AppTheme(
    id: 'ocean',
    name: 'Ocean',
    subtitle: 'Calm and refreshing',
    bg: Color(0xFF08121E),
    surface: Color(0xFF0F2235),
    surfaceTeal: Color(0xFF0A2B3A),
    primary: Color(0xFF06B6D4),
    secondary: Color(0xFF3B82F6),
    gradientStart: Color(0xFF06B6D4),
    gradientEnd: Color(0xFF2DD4BF),
    textPrimary: Colors.white,
    textMuted: Color(0x99FFFFFF),
    border: Color(0x2006B6D4),
    glow: Color(0x3306B6D4),
    bubbleSelf: Color(0xFF0284C7),
    bubblePartner: Color(0xFF0F2235),
  );

  static const AppTheme lavenderTheme = AppTheme(
    id: 'lavender',
    name: 'Lavender',
    subtitle: 'Soft and elegant',
    bg: Color(0xFF110C1D),
    surface: Color(0xFF201633),
    surfaceTeal: Color(0xFF1B172E),
    primary: Color(0xFFA855F7),
    secondary: Color(0xFFEC4899),
    gradientStart: Color(0xFFA855F7),
    gradientEnd: Color(0xFFEC4899),
    textPrimary: Colors.white,
    textMuted: Color(0x99FFFFFF),
    border: Color(0x24A855F7),
    glow: Color(0x33A855F7),
    bubbleSelf: Color(0xFF9333EA),
    bubblePartner: Color(0xFF201633),
  );

  static const AppTheme emeraldTheme = AppTheme(
    id: 'emerald',
    name: 'Emerald',
    subtitle: 'Elegant and natural',
    bg: Color(0xFF071410),
    surface: Color(0xFF11261E),
    surfaceTeal: Color(0xFF0D3025),
    primary: Color(0xFF10B981),
    secondary: Color(0xFF06B6D4),
    gradientStart: Color(0xFF10B981),
    gradientEnd: Color(0xFF059669),
    textPrimary: Colors.white,
    textMuted: Color(0x99FFFFFF),
    border: Color(0x2010B981),
    glow: Color(0x3310B981),
    bubbleSelf: Color(0xFF059669),
    bubblePartner: Color(0xFF11261E),
  );

  static const AppTheme sunsetTheme = AppTheme(
    id: 'sunset',
    name: 'Sunset',
    subtitle: 'Warm and expressive',
    bg: Color(0xFF130D18),
    surface: Color(0xFF251728),
    surfaceTeal: Color(0xFF2A1C20),
    primary: Color(0xFFF97316),
    secondary: Color(0xFFE11D48),
    gradientStart: Color(0xFFF97316),
    gradientEnd: Color(0xFFE11D48),
    textPrimary: Colors.white,
    textMuted: Color(0x99FFFFFF),
    border: Color(0x24F97316),
    glow: Color(0x33F97316),
    bubbleSelf: Color(0xFFEA580C),
    bubblePartner: Color(0xFF251728),
  );

  static const List<AppTheme> allThemes = [
    defaultTheme,
    midnightTheme,
    roseTheme,
    oceanTheme,
    lavenderTheme,
    emeraldTheme,
    sunsetTheme,
  ];

  static AppTheme fromId(String id) {
    return allThemes.firstWhere(
      (theme) => theme.id == id,
      orElse: () => defaultTheme,
    );
  }
}
