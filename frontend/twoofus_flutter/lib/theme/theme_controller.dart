import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class ThemeController {
  ThemeController._();

  static const String _themeStorageKey = "selected_theme_id";

  /// Reactive current theme state listened to by MaterialApp and UI components
  static final ValueNotifier<AppTheme> currentTheme =
      ValueNotifier<AppTheme>(AppTheme.defaultTheme);

  /// Load persisted theme from SharedPreferences on app launch
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_themeStorageKey);
      if (savedId != null && savedId.isNotEmpty) {
        currentTheme.value = AppTheme.fromId(savedId);
      }
    } catch (e) {
      currentTheme.value = AppTheme.defaultTheme;
    }
  }

  /// Switch current theme live and persist choice
  static Future<void> setTheme(AppTheme theme) async {
    currentTheme.value = theme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeStorageKey, theme.id);
    } catch (_) {}
  }

  /// Generate Material 3 ThemeData from AppTheme for system integration
  static ThemeData buildThemeData(AppTheme theme) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: theme.bg,
      colorScheme: ColorScheme.dark(
        surface: theme.surface,
        primary: theme.primary,
        secondary: theme.secondary,
        onSurface: theme.textPrimary,
        outline: theme.border,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: theme.textPrimary),
        titleTextStyle: TextStyle(
          color: theme.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: theme.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: theme.border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: theme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: theme.border, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: theme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(
          color: theme.textMuted,
          fontSize: 14,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: theme.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: theme.surfaceElevated,
        contentTextStyle: TextStyle(color: theme.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: theme.border),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: theme.glow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: theme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: theme.border,
        thickness: 1,
      ),
      iconTheme: IconThemeData(
        color: theme.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: theme.surface,
        hintStyle: TextStyle(color: theme.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: theme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: theme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: theme.primary, width: 1.5),
        ),
      ),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppTheme get appTheme => ThemeController.currentTheme.value;
}

