import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoofus_flutter/theme/app_theme.dart';
import 'package:twoofus_flutter/theme/theme_controller.dart';

double _luminance(Color color) {
  double channel(double c) {
    c = c / 255.0;
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r * 255.0) +
      0.7152 * channel(color.g * 255.0) +
      0.0722 * channel(color.b * 255.0);
}

double _contrastRatio(Color c1, Color c2) {
  final l1 = _luminance(c1);
  final l2 = _luminance(c2);
  final lighter = max(l1, l2);
  final darker = min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Theme Migration Tests', () {
    const legacyThemeIds = [
      'default',
      'midnight',
      'rose',
      'ocean',
      'lavender',
      'emerald',
      'sunset',
    ];

    for (final legacyId in legacyThemeIds) {
      test('Migrates legacy theme id "$legacyId" to default accent + dark brightness', () async {
        SharedPreferences.setMockInitialValues({
          'selected_theme_id': legacyId,
        });

        await ThemeController.init();

        expect(ThemeController.currentAccent.value, equals(AppAccent.indigo));
        expect(ThemeController.currentThemeMode.value, equals(ThemeMode.dark));
        expect(ThemeController.currentTheme.value.brightness, equals(Brightness.dark));
        expect(ThemeController.currentTheme.value.accent, equals(AppAccent.indigo));
        expect(ThemeController.currentTheme.value.id, equals('dark_indigo'));

        // Check that updated values were persisted back
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_theme_id'), equals('dark_indigo'));
        expect(prefs.getString('selected_theme_mode'), equals('dark'));
        expect(prefs.getString('selected_theme_accent'), equals('indigo'));
      });
    }

    test('Preserves modern theme id like "light_teal"', () async {
      SharedPreferences.setMockInitialValues({
        'selected_theme_id': 'light_teal',
        'selected_theme_mode': 'light',
        'selected_theme_accent': 'teal',
      });

      await ThemeController.init();

      expect(ThemeController.currentAccent.value, equals(AppAccent.teal));
      expect(ThemeController.currentThemeMode.value, equals(ThemeMode.light));
      expect(ThemeController.currentTheme.value.brightness, equals(Brightness.light));
      expect(ThemeController.currentTheme.value.accent, equals(AppAccent.teal));
    });
  });

  group('WCAG Contrast Ratio Automated Verification', () {
    test('textTertiary passes >= 4.5:1 on darkBg and darkSurface in all dark themes', () {
      for (final accent in AppAccent.values) {
        final theme = AppTheme.dark(accent);
        final ratioOnBg = _contrastRatio(theme.textTertiary, theme.bg);
        final ratioOnSurface = _contrastRatio(theme.textTertiary, theme.surface);
        final ratioOnRaised = _contrastRatio(theme.textTertiary, theme.surfaceRaised);

        expect(ratioOnBg, greaterThanOrEqualTo(4.5),
            reason: 'textTertiary on darkBg for $accent must be >= 4.5');
        expect(ratioOnSurface, greaterThanOrEqualTo(4.5),
            reason: 'textTertiary on darkSurface for $accent must be >= 4.5');
        expect(ratioOnRaised, greaterThanOrEqualTo(4.5),
            reason: 'textTertiary on darkSurfaceRaised for $accent must be >= 4.5');
      }
    });

    test('textTertiary passes >= 4.5:1 on lightBg and lightSurface in all light themes', () {
      for (final accent in AppAccent.values) {
        final theme = AppTheme.light(accent);
        final ratioOnBg = _contrastRatio(theme.textTertiary, theme.bg);
        final ratioOnSurface = _contrastRatio(theme.textTertiary, theme.surface);

        expect(ratioOnBg, greaterThanOrEqualTo(4.5),
            reason: 'textTertiary on lightBg for $accent must be >= 4.5');
        expect(ratioOnSurface, greaterThanOrEqualTo(4.5),
            reason: 'textTertiary on lightSurface for $accent must be >= 4.5');
      }
    });

    test('accentFill passes >= 4.5:1 with onAccent in BOTH dark and light', () {
      for (final accent in AppAccent.values) {
        for (final brightness in [Brightness.dark, Brightness.light]) {
          final theme = brightness == Brightness.dark ? AppTheme.dark(accent) : AppTheme.light(accent);
          final ratio = _contrastRatio(theme.onAccent, theme.accentFill);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'onAccent vs accentFill for $accent ($brightness) must be >= 4.5:1 (got $ratio)');
        }
      }
    });

    test('accentBright passes >= 3.0:1 on darkSurface for icons and borders', () {
      for (final accent in AppAccent.values) {
        final theme = AppTheme.dark(accent);
        final ratio = _contrastRatio(theme.accentBright, theme.surface);
        expect(ratio, greaterThanOrEqualTo(3.0),
            reason: 'accentBright vs darkSurface for $accent must be >= 3.0:1 (got $ratio)');
      }
    });

    test('compute and print ratios for accentFill vs darkBg, darkSurface, darkSurfaceRaised, lightBg', () {
      for (final accent in AppAccent.values) {
        final dark = AppTheme.dark(accent);
        final light = AppTheme.light(accent);
        final fill = accent.fillColor;
        final vsDarkBg = _contrastRatio(fill, dark.bg);
        final vsDarkSurf = _contrastRatio(fill, dark.surface);
        final vsDarkRaised = _contrastRatio(fill, dark.surfaceRaised);
        final vsLightBg = _contrastRatio(fill, light.bg);
        // ignore: avoid_print
        print('CONTRAST_DATA: ${accent.name} | darkBg: ${vsDarkBg.toStringAsFixed(2)}:1 | darkSurface: ${vsDarkSurf.toStringAsFixed(2)}:1 | darkRaised: ${vsDarkRaised.toStringAsFixed(2)}:1 | lightBg: ${vsLightBg.toStringAsFixed(2)}:1');
      }
    });
  });
}
