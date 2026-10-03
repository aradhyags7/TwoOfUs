import 'package:flutter/material.dart';

class AppTheme {
  final String id;
  final String name;
  final String subtitle;
  final String moodEmoji;

  final Color bg;
  final Color surface;
  final Color surfaceElevated;
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
    this.moodEmoji = '💖',
    required this.bg,
    required this.surface,
    this.surfaceElevated = const Color(0xFF221A35),
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

  LinearGradient get gradient => LinearGradient(
        colors: [gradientStart, gradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get cardGradient => LinearGradient(
        colors: [surface, surfaceElevated],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // ── 1. Classic Velvet (Signature Romantic Noir) ───────────────────────────
  static const AppTheme defaultTheme = AppTheme(
    id: 'default',
    name: 'Velvet Romance',
    subtitle: 'Signature deep amethyst & radiant rose',
    moodEmoji: '💖',
    bg: Color(0xFF0C0914),
    surface: Color(0xFF171126),
    surfaceElevated: Color(0xFF221938),
    surfaceTeal: Color(0xFF12232B),
    primary: Color(0xFFFF3370),
    secondary: Color(0xFF8B5CF6),
    gradientStart: Color(0xFFFF3370),
    gradientEnd: Color(0xFF8B5CF6),
    textPrimary: Color(0xFFF8FAFC),
    textMuted: Color(0xFF94A3B8),
    border: Color(0x338B5CF6),
    glow: Color(0x40FF3370),
    bubbleSelf: Color(0xFF8B5CF6),
    bubblePartner: Color(0xFF1E1730),
  );

  // ── 2. Midnight Cyber (Deep Space & Neon Cyan) ────────────────────────────
  static const AppTheme midnightTheme = AppTheme(
    id: 'midnight',
    name: 'Midnight Cyber',
    subtitle: 'Obsidian black with bioluminescent cyan',
    moodEmoji: '🌌',
    bg: Color(0xFF07090F),
    surface: Color(0xFF0E1422),
    surfaceElevated: Color(0xFF161F33),
    surfaceTeal: Color(0xFF0D2533),
    primary: Color(0xFF00E5FF),
    secondary: Color(0xFF6366F1),
    gradientStart: Color(0xFF00E5FF),
    gradientEnd: Color(0xFF6366F1),
    textPrimary: Color(0xFFF1F5F9),
    textMuted: Color(0xFF94A3B8),
    border: Color(0x3300E5FF),
    glow: Color(0x4000E5FF),
    bubbleSelf: Color(0xFF4F46E5),
    bubblePartner: Color(0xFF121B2E),
  );

  // ── 3. Sakura Bloom (Warm Cherry Blossom) ──────────────────────────────────
  static const AppTheme roseTheme = AppTheme(
    id: 'rose',
    name: 'Sakura Bloom',
    subtitle: 'Warm wine espresso & radiant cherry blossom',
    moodEmoji: '🌸',
    bg: Color(0xFF11080E),
    surface: Color(0xFF1D0E18),
    surfaceElevated: Color(0xFF2B1424),
    surfaceTeal: Color(0xFF1C1D24),
    primary: Color(0xFFFB7185),
    secondary: Color(0xFFE879F9),
    gradientStart: Color(0xFFFB7185),
    gradientEnd: Color(0xFFE879F9),
    textPrimary: Color(0xFFFFF1F2),
    textMuted: Color(0xFFE2C4D2),
    border: Color(0x33FB7185),
    glow: Color(0x40FB7185),
    bubbleSelf: Color(0xFFE11D48),
    bubblePartner: Color(0xFF261220),
  );

  // ── 4. Twilight Abyss (Royal Sapphire & Ocean) ─────────────────────────────
  static const AppTheme oceanTheme = AppTheme(
    id: 'ocean',
    name: 'Twilight Abyss',
    subtitle: 'Serene deep ocean & azure bioluminescence',
    moodEmoji: '🌊',
    bg: Color(0xFF040B16),
    surface: Color(0xFF0A172B),
    surfaceElevated: Color(0xFF112442),
    surfaceTeal: Color(0xFF0C2B3D),
    primary: Color(0xFF38BDF8),
    secondary: Color(0xFF3B82F6),
    gradientStart: Color(0xFF38BDF8),
    gradientEnd: Color(0xFF2563EB),
    textPrimary: Color(0xFFF0F9FF),
    textMuted: Color(0xFF93C5FD),
    border: Color(0x3338BDF8),
    glow: Color(0x4038BDF8),
    bubbleSelf: Color(0xFF0284C7),
    bubblePartner: Color(0xFF0E203B),
  );

  // ── 5. Moonlight Lavender (Lilac & Soft Orchid) ───────────────────────────
  static const AppTheme lavenderTheme = AppTheme(
    id: 'lavender',
    name: 'Moonlight Lilac',
    subtitle: 'Dreamy midnight violet & glowing orchid',
    moodEmoji: '🌙',
    bg: Color(0xFF0B0716),
    surface: Color(0xFF17102A),
    surfaceElevated: Color(0xFF23193E),
    surfaceTeal: Color(0xFF171D2E),
    primary: Color(0xFFC084FC),
    secondary: Color(0xFFF472B6),
    gradientStart: Color(0xFFC084FC),
    gradientEnd: Color(0xFFF472B6),
    textPrimary: Color(0xFFFAF5FF),
    textMuted: Color(0xFFC4B5FD),
    border: Color(0x33C084FC),
    glow: Color(0x40C084FC),
    bubbleSelf: Color(0xFF9333EA),
    bubblePartner: Color(0xFF1E1535),
  );

  // ── 6. Nordic Aurora (Emerald & Arctic Jade) ──────────────────────────────
  static const AppTheme emeraldTheme = AppTheme(
    id: 'emerald',
    name: 'Nordic Aurora',
    subtitle: 'Pine forest midnight & luminous jade aurora',
    moodEmoji: '🌿',
    bg: Color(0xFF040F0C),
    surface: Color(0xFF0B1E18),
    surfaceElevated: Color(0xFF122C24),
    surfaceTeal: Color(0xFF0C2B22),
    primary: Color(0xFF10B981),
    secondary: Color(0xFF06B6D4),
    gradientStart: Color(0xFF10B981),
    gradientEnd: Color(0xFF2DD4BF),
    textPrimary: Color(0xFFF0FDF4),
    textMuted: Color(0xFF94B8A3),
    border: Color(0x3310B981),
    glow: Color(0x4010B981),
    bubbleSelf: Color(0xFF059669),
    bubblePartner: Color(0xFF0F261E),
  );

  // ── 7. Golden Sunset (Warm Amber & Ruby Rose) ──────────────────────────────
  static const AppTheme sunsetTheme = AppTheme(
    id: 'sunset',
    name: 'Golden Sunset',
    subtitle: 'Warm cedar espresso & glowing twilight amber',
    moodEmoji: '🌅',
    bg: Color(0xFF100906),
    surface: Color(0xFF20120B),
    surfaceElevated: Color(0xFF2E1A11),
    surfaceTeal: Color(0xFF281C1B),
    primary: Color(0xFFF97316),
    secondary: Color(0xFFF43F5E),
    gradientStart: Color(0xFFF97316),
    gradientEnd: Color(0xFFE11D48),
    textPrimary: Color(0xFFFFF7ED),
    textMuted: Color(0xFFD4B09E),
    border: Color(0x33F97316),
    glow: Color(0x40F97316),
    bubbleSelf: Color(0xFFEA580C),
    bubblePartner: Color(0xFF26160F),
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
