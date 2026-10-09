import 'package:flutter/material.dart';

/// Supported accent themes in TwoOfUs design system.
/// Every accent fill passes WCAG AA >= 4.5:1 with white text in BOTH light & dark modes.
enum AppAccent {
  indigo(
    id: 'indigo',
    name: 'Indigo',
    subtitle: 'Quiet slate & electric indigo',
    fillColor: Color(0xFF4F46E5),   // Indigo-600 (vs White: 6.29:1)
    brightColor: Color(0xFF818CF8), // Indigo-400 (vs DarkSurface: 6.03:1)
  ),
  teal(
    id: 'teal',
    name: 'Teal',
    subtitle: 'Balanced obsidian & radiant teal',
    fillColor: Color(0xFF0F766E),   // Teal-700 (vs White: 5.47:1)
    brightColor: Color(0xFF2DD4BF), // Teal-400 (vs DarkSurface: 9.66:1)
  ),
  rose(
    id: 'rose',
    name: 'Rose',
    subtitle: 'Deep crimson & soft rose',
    fillColor: Color(0xFFBE123C),   // Rose-700 (vs White: 6.29:1)
    brightColor: Color(0xFFFB7185), // Rose-400 (vs DarkSurface: 6.68:1)
  ),
  amber(
    id: 'amber',
    name: 'Amber',
    subtitle: 'Warm espresso & honey amber',
    fillColor: Color(0xFF92400E),   // Amber-800 (vs White: 7.09:1)
    brightColor: Color(0xFFFBBF24), // Amber-400 (vs DarkSurface: 10.77:1)
  ),
  graphite(
    id: 'graphite',
    name: 'Graphite',
    subtitle: 'Monochrome slate & zinc',
    fillColor: Color(0xFF334155),   // Slate-700 (vs White: 10.35:1)
    brightColor: Color(0xFF94A3B8), // Slate-400 (vs DarkSurface: 7.01:1)
  );

  const AppAccent({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.fillColor,
    required this.brightColor,
  });

  final String id;
  final String name;
  final String subtitle;
  final Color fillColor;
  final Color brightColor;

  String get label => name;

  /// Contrast-validated foreground color for accent fills.
  /// Passes >= 4.5:1 in both light and dark.
  Color onAccent(Brightness brightness) => Colors.white;

  static AppAccent fromId(String id) {
    return AppAccent.values.firstWhere(
      (accent) => accent.id == id,
      orElse: () => AppAccent.indigo,
    );
  }
}

/// Central Theme Tokens for TwoOfUs.
/// Strict WCAG AA compliance, neutral-first palette, zero neon glow, 1px hairlines.
class AppTheme {
  // Metadata
  final String id;
  final String name;
  final String subtitle;
  final String moodEmoji;
  final Brightness brightness;
  final AppAccent accent;

  // Backgrounds & Canvas
  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceElevated; // Backward compatibility alias for surfaceRaised
  final Color surfaceTeal;     // Backward compatibility alias

  // Borders & Dividers
  final Color border;
  final Color borderSubtle;
  final Color divider;

  // Typography Tokens (Strict contrast: primary >= 12:1, secondary >= 7:1, tertiary >= 5:1)
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textMuted;       // Backward compatibility alias for textTertiary

  // Accents & Interactions
  final Color primary;
  final Color secondary;
  final Color accentFill;
  final Color accentBright;
  final Color accentBorder;
  final Color onAccent;
  final Color focusRing;

  // Bubbles
  final Color bubbleSelf;      // Backward compatibility alias for bubbleSent
  final Color bubblePartner;   // Backward compatibility alias for bubbleReceived
  final Color bubbleSent;
  final Color bubbleReceived;
  final Color onBubbleSent;
  final Color onBubbleReceived;

  // Semantics
  final Color danger;
  final Color success;
  final Color warning;

  // Shadows / Glow (Set to transparent across all themes to remove AI neon glows)
  final Color glow;

  // Gradients (Solid/flat or subtle ramps, no rainbow AI gradients)
  final Color gradientStart;
  final Color gradientEnd;

  const AppTheme({
    required this.id,
    required this.name,
    required this.subtitle,
    this.moodEmoji = '💬',
    required this.brightness,
    required this.accent,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceElevated,
    required this.surfaceTeal,
    required this.border,
    required this.borderSubtle,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
    required this.primary,
    required this.secondary,
    required this.accentFill,
    required this.accentBright,
    this.accentBorder = Colors.transparent,
    required this.onAccent,
    required this.focusRing,
    required this.bubbleSelf,
    required this.bubblePartner,
    required this.bubbleSent,
    required this.bubbleReceived,
    required this.onBubbleSent,
    required this.onBubbleReceived,
    required this.danger,
    required this.success,
    required this.warning,
    required this.glow,
    required this.gradientStart,
    required this.gradientEnd,
  });

  bool get isDark => brightness == Brightness.dark;

  LinearGradient get gradient => LinearGradient(
        colors: [accentFill, accentFill],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get cardGradient => LinearGradient(
        colors: [surface, surface],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // ── Factory Constructors ───────────────────────────────────────────────────

  /// Build a Dark Theme instance for any accent
  factory AppTheme.dark(AppAccent accent) {
    const bgDark = Color(0xFF0E1013);
    const surfaceDark = Color(0xFF14171B);
    const surfaceRaisedDark = Color(0xFF1A1E23);
    const borderDark = Color(0xFF262B32);
    const borderSubtleDark = Color(0xFF1E232A);
    const dividerDark = Color(0xFF1D2127);

    const textPrimaryDark = Color(0xFFF1F5F9);
    const textSecondaryDark = Color(0xFF94A3B8);
    // Measured 6.31:1 on bgDark, 5.96:1 on surfaceDark (passes >= 4.5:1)
    const textTertiaryDark = Color(0xFF8896A6);

    final fill = accent.fillColor;
    final bright = accent.brightColor;

    return AppTheme(
      id: 'dark_${accent.id}',
      name: '${accent.name} Dark',
      subtitle: accent.subtitle,
      moodEmoji: '🌙',
      brightness: Brightness.dark,
      accent: accent,
      bg: bgDark,
      surface: surfaceDark,
      surfaceRaised: surfaceRaisedDark,
      surfaceElevated: surfaceRaisedDark,
      surfaceTeal: surfaceDark,
      border: borderDark,
      borderSubtle: borderSubtleDark,
      divider: dividerDark,
      textPrimary: textPrimaryDark,
      textSecondary: textSecondaryDark,
      textTertiary: textTertiaryDark,
      textMuted: textTertiaryDark,
      primary: bright,
      secondary: bright,
      accentFill: fill,
      accentBright: bright,
      accentBorder: bright.withValues(alpha: 0.35),
      onAccent: accent.onAccent(Brightness.dark),
      focusRing: bright,
      bubbleSelf: fill,
      bubblePartner: surfaceRaisedDark,
      bubbleSent: fill,
      bubbleReceived: surfaceRaisedDark,
      onBubbleSent: Colors.white,
      onBubbleReceived: textPrimaryDark,
      danger: const Color(0xFFEF4444),
      success: const Color(0xFF10B981),
      warning: const Color(0xFFF59E0B),
      glow: Colors.transparent, // Zero blur glow
      gradientStart: fill,
      gradientEnd: bright,
    );
  }

  /// Build a Light Theme instance for any accent
  factory AppTheme.light(AppAccent accent) {
    const bgLight = Color(0xFFF6F7F9);
    const surfaceLight = Color(0xFFFFFFFF);
    const surfaceRaisedLight = Color(0xFFF0F2F5);
    const borderLight = Color(0xFFE2E8F0);
    const borderSubtleLight = Color(0xFFEDF2F7);
    const dividerLight = Color(0xFFE2E8F0);

    const textPrimaryLight = Color(0xFF0F172A);
    const textSecondaryLight = Color(0xFF475569);
    // Measured 5.30:1 on bgLight, 5.68:1 on surfaceLight (passes >= 4.5:1)
    const textTertiaryLight = Color(0xFF5A687A);

    final fill = accent.fillColor;
    final bright = accent.brightColor;

    return AppTheme(
      id: 'light_${accent.id}',
      name: '${accent.name} Light',
      subtitle: accent.subtitle,
      moodEmoji: '☀️',
      brightness: Brightness.light,
      accent: accent,
      bg: bgLight,
      surface: surfaceLight,
      surfaceRaised: surfaceRaisedLight,
      surfaceElevated: surfaceRaisedLight,
      surfaceTeal: surfaceLight,
      border: borderLight,
      borderSubtle: borderSubtleLight,
      divider: dividerLight,
      textPrimary: textPrimaryLight,
      textSecondary: textSecondaryLight,
      textTertiary: textTertiaryLight,
      textMuted: textTertiaryLight,
      primary: fill,
      secondary: fill,
      accentFill: fill,
      accentBright: bright,
      onAccent: accent.onAccent(Brightness.light),
      focusRing: fill,
      bubbleSelf: fill,
      bubblePartner: surfaceLight,
      bubbleSent: fill,
      bubbleReceived: surfaceLight,
      onBubbleSent: Colors.white,
      onBubbleReceived: textPrimaryLight,
      danger: const Color(0xFFDC2626),
      success: const Color(0xFF059669),
      warning: const Color(0xFFD97706),
      glow: Colors.transparent, // Zero blur glow
      gradientStart: fill,
      gradientEnd: fill,
    );
  }

  // ── Preset Themes ──────────────────────────────────────────────────────────

  /// Default theme: Dark + Indigo accent
  static final AppTheme defaultTheme = AppTheme.dark(AppAccent.indigo);

  static final AppTheme darkIndigo = AppTheme.dark(AppAccent.indigo);
  static final AppTheme darkTeal = AppTheme.dark(AppAccent.teal);
  static final AppTheme darkRose = AppTheme.dark(AppAccent.rose);
  static final AppTheme darkAmber = AppTheme.dark(AppAccent.amber);
  static final AppTheme darkGraphite = AppTheme.dark(AppAccent.graphite);

  static final AppTheme lightIndigo = AppTheme.light(AppAccent.indigo);
  static final AppTheme lightTeal = AppTheme.light(AppAccent.teal);
  static final AppTheme lightRose = AppTheme.light(AppAccent.rose);
  static final AppTheme lightAmber = AppTheme.light(AppAccent.amber);
  static final AppTheme lightGraphite = AppTheme.light(AppAccent.graphite);

  static final List<AppTheme> allThemes = [
    darkIndigo,
    darkTeal,
    darkRose,
    darkAmber,
    darkGraphite,
    lightIndigo,
    lightTeal,
    lightRose,
    lightAmber,
    lightGraphite,
  ];

  /// Backward compatible legacy presets pointing directly to modern tokens
  static final AppTheme midnightTheme = AppTheme.dark(AppAccent.indigo);
  static final AppTheme roseTheme = AppTheme.dark(AppAccent.rose);
  static final AppTheme oceanTheme = AppTheme.dark(AppAccent.teal);
  static final AppTheme lavenderTheme = AppTheme.dark(AppAccent.indigo);
  static final AppTheme emeraldTheme = AppTheme.dark(AppAccent.teal);
  static final AppTheme sunsetTheme = AppTheme.dark(AppAccent.amber);

  /// Resolves any theme ID (legacy or modern) safely
  static AppTheme fromId(String id) {
    // Migration: Map legacy theme IDs to default Dark Indigo
    const legacyIds = {
      'default',
      'midnight',
      'rose',
      'ocean',
      'lavender',
      'emerald',
      'sunset',
    };
    if (legacyIds.contains(id)) {
      return AppTheme.dark(AppAccent.indigo);
    }

    // Direct match
    return allThemes.firstWhere(
      (theme) => theme.id == id,
      orElse: () => defaultTheme,
    );
  }

  /// Resolve theme for given brightness and accent
  static AppTheme resolve({
    required Brightness brightness,
    required AppAccent accent,
  }) {
    return brightness == Brightness.dark
        ? AppTheme.dark(accent)
        : AppTheme.light(accent);
  }
}

/// Standalone access to design tokens and semantic colors
abstract final class AppColors {
  static const Color darkBg = Color(0xFF0E1013);
  static const Color darkSurface = Color(0xFF14171B);
  static const Color darkSurfaceRaised = Color(0xFF1A1E23);
  static const Color darkBorder = Color(0xFF262C34);
  static const Color darkBorderSubtle = Color(0xFF1E232A);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFFB0BCCB);
  static const Color darkTextTertiary = Color(0xFF8896A6);
  static const Color darkSuccess = Color(0xFF10B981);
  static const Color darkWarning = Color(0xFFF59E0B);
  static const Color darkDanger = Color(0xFFEF4444);

  static const Color lightBg = Color(0xFFF6F7F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceRaised = Color(0xFFF0F2F5);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightBorderSubtle = Color(0xFFECEFF3);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF334155);
  static const Color lightTextTertiary = Color(0xFF5A687A);
  static const Color lightSuccess = Color(0xFF059669);
  static const Color lightWarning = Color(0xFFD97706);
  static const Color lightDanger = Color(0xFFDC2626);
}
