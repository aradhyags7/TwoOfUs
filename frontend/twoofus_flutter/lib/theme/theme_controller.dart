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
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: theme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: theme.surface,
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
