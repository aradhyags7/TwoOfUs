import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class ThemeController {
  ThemeController._();

  static const String _legacyThemeStorageKey = "selected_theme_id";
  static const String _themeModeStorageKey = "selected_theme_mode";
  static const String _themeAccentStorageKey = "selected_theme_accent";

  /// Current active accent
  static final ValueNotifier<AppAccent> currentAccent =
      ValueNotifier<AppAccent>(AppAccent.indigo);

  /// Current theme mode (system, light, dark)
  static final ValueNotifier<ThemeMode> currentThemeMode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  /// Reactive current theme state listened to by MaterialApp and UI components
  static final ValueNotifier<AppTheme> currentTheme =
      ValueNotifier<AppTheme>(AppTheme.defaultTheme);

  /// Check if the passed ID is a legacy theme ID from the previous design
  static bool isLegacyThemeId(String id) {
    const legacy = {
      'default',
      'midnight',
      'rose',
      'ocean',
      'lavender',
      'emerald',
      'sunset',
    };
    return legacy.contains(id);
  }

  /// Initialize theme on app launch and migrate any old theme ID in SharedPreferences
  /// Maps old theme ID to default accent (indigo) + dark brightness.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLegacyId = prefs.getString(_legacyThemeStorageKey);
      final savedModeStr = prefs.getString(_themeModeStorageKey);
      final savedAccentStr = prefs.getString(_themeAccentStorageKey);

      // Rule 5: Migrate legacy theme IDs to default accent (indigo) + dark brightness
      if (savedLegacyId != null && isLegacyThemeId(savedLegacyId)) {
        currentAccent.value = AppAccent.indigo;
        currentThemeMode.value = ThemeMode.dark;
        currentTheme.value = AppTheme.dark(AppAccent.indigo);

        await prefs.setString(_legacyThemeStorageKey, 'dark_indigo');
        await prefs.setString(_themeModeStorageKey, 'dark');
        await prefs.setString(_themeAccentStorageKey, 'indigo');
        updateSystemUiOverlay();
        return;
      }

      // Restore accent
      AppAccent resolvedAccent = AppAccent.indigo;
      if (savedAccentStr != null && savedAccentStr.isNotEmpty) {
        resolvedAccent = AppAccent.fromId(savedAccentStr);
      } else if (savedLegacyId != null) {
        for (final a in AppAccent.values) {
          if (savedLegacyId.contains(a.id)) {
            resolvedAccent = a;
            break;
          }
        }
      }

      // Restore mode
      ThemeMode resolvedMode = ThemeMode.dark;
      if (savedModeStr == 'light') {
        resolvedMode = ThemeMode.light;
      } else if (savedModeStr == 'system') {
        resolvedMode = ThemeMode.system;
      } else if (savedModeStr == 'dark') {
        resolvedMode = ThemeMode.dark;
      } else if (savedLegacyId != null && savedLegacyId.startsWith('light_')) {
        resolvedMode = ThemeMode.light;
      }

      currentAccent.value = resolvedAccent;
      currentThemeMode.value = resolvedMode;

      final Brightness activeBrightness = resolveActiveBrightness(resolvedMode);
      currentTheme.value = AppTheme.resolve(
        brightness: activeBrightness,
        accent: resolvedAccent,
      );
      updateSystemUiOverlay();
    } catch (_) {
      currentAccent.value = AppAccent.indigo;
      currentThemeMode.value = ThemeMode.dark;
      currentTheme.value = AppTheme.defaultTheme;
      updateSystemUiOverlay();
    }
  }

  /// Resolves effective brightness for a given ThemeMode
  static Brightness resolveActiveBrightness([ThemeMode? mode]) {
    final effectiveMode = mode ?? currentThemeMode.value;
    if (effectiveMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
    return effectiveMode == ThemeMode.light ? Brightness.light : Brightness.dark;
  }

  /// Update SystemUiOverlayStyle (status bar and nav bar icon brightness) from active brightness
  static void updateSystemUiOverlay([Brightness? overrideBrightness]) {
    final Brightness brightness = overrideBrightness ?? resolveActiveBrightness();
    final bool isDark = brightness == Brightness.dark;
    final theme = currentTheme.value;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: theme.bg,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  /// Update mode & accent and persist
  static Future<void> setThemeConfig({
    ThemeMode? mode,
    AppAccent? accent,
  }) async {
    if (mode != null) currentThemeMode.value = mode;
    if (accent != null) currentAccent.value = accent;

    final brightness = resolveActiveBrightness(currentThemeMode.value);
    final newTheme = AppTheme.resolve(
      brightness: brightness,
      accent: currentAccent.value,
    );
    currentTheme.value = newTheme;
    updateSystemUiOverlay(brightness);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_legacyThemeStorageKey, newTheme.id);
      await prefs.setString(_themeAccentStorageKey, currentAccent.value.id);
      await prefs.setString(
        _themeModeStorageKey,
        currentThemeMode.value == ThemeMode.light
            ? 'light'
            : currentThemeMode.value == ThemeMode.system
                ? 'system'
                : 'dark',
      );
    } catch (_) {}
  }

  /// Backward compatible setTheme(AppTheme theme)
  static Future<void> setTheme(AppTheme theme) async {
    final mode = theme.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
    await setThemeConfig(mode: mode, accent: theme.accent);
  }

  /// Called when system platform brightness changes (for System mode)
  static void handlePlatformBrightnessChange() {
    if (currentThemeMode.value == ThemeMode.system) {
      final brightness = resolveActiveBrightness(ThemeMode.system);
      currentTheme.value = AppTheme.resolve(
        brightness: brightness,
        accent: currentAccent.value,
      );
      updateSystemUiOverlay(brightness);
    }
  }

  /// Generate Material 3 ThemeData with bundled Inter font and zero glow
  static ThemeData buildThemeData(AppTheme theme) {
    final isDark = theme.isDark;

    return ThemeData(
      useMaterial3: true,
      brightness: theme.brightness,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: theme.bg,
      colorScheme: ColorScheme(
        brightness: theme.brightness,
        primary: theme.accentFill,
        onPrimary: theme.onAccent,
        secondary: theme.accentBright,
        onSecondary: isDark ? const Color(0xFF0E1013) : Colors.white,
        surface: theme.surface,
        onSurface: theme.textPrimary,
        error: theme.danger,
        onError: Colors.white,
        outline: theme.border,
        outlineVariant: theme.borderSubtle,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: theme.textPrimary, size: 22),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: theme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: theme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: theme.surfaceRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.border, width: 1),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: theme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: theme.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: theme.surfaceRaised,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: theme.surfaceRaised,
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: theme.textPrimary,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.border, width: 1),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.accentFill,
          foregroundColor: theme.onAccent,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: -0.1,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? theme.accentBright : theme.accentFill,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: theme.divider,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(
        color: theme.textPrimary,
        size: 22,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: theme.surfaceRaised,
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          color: theme.textTertiary,
          fontSize: 14,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.focusRing, width: 1.5),
        ),
      ),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppTheme get appTheme => ThemeController.currentTheme.value;
}
