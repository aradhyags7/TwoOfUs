import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/design_system/design_system.dart';

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        final isDark = activeTheme.brightness == Brightness.dark;
        final currentMode = ThemeController.currentThemeMode.value;
        final currentAccent = ThemeController.currentAccent.value;

        return Scaffold(
          backgroundColor: activeTheme.bg,
          appBar: AppBar(
            backgroundColor: activeTheme.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                color: activeTheme.textPrimary,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Appearance",
              style: TextStyle(
                color: activeTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: -0.2,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ── 1. Live Interactive Preview ─────────────────────────────────
              _buildLivePreview(activeTheme, isDark),
              const SizedBox(height: 24),

              // ── 2. Mode Selector (System / Dark / Light) ────────────────────
              Text(
                "THEME MODE",
                style: TextStyle(
                  color: activeTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              _buildModeSelector(context, activeTheme, currentMode),
              const SizedBox(height: 24),

              // ── 3. Accent Color Swatches ────────────────────────────────────
              Text(
                "ACCENT COLOR",
                style: TextStyle(
                  color: activeTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              _buildAccentPicker(activeTheme, currentAccent),
              const SizedBox(height: 24),

              // ── 4. Theme Presets ───────────────────────────────────────────
              SectionGroup(
                title: "Curated Presets",
                children: AppTheme.allThemes.map((theme) {
                  final isSelected = activeTheme.id == theme.id;
                  return AppListTile(
                    title: theme.name,
                    subtitle: "${theme.brightness == Brightness.dark ? 'Dark' : 'Light'} • ${theme.accent.label}",
                    leading: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: theme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? activeTheme.textPrimary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: activeTheme.primary, size: 20)
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ThemeController.setTheme(theme);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Mode Selector ─────────────────────────────────────────────────────────
  Widget _buildModeSelector(
    BuildContext context,
    AppTheme theme,
    ThemeMode currentMode,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        children: [
          _buildModeTab(
            label: "System",
            icon: Icons.brightness_auto_rounded,
            isSelected: currentMode == ThemeMode.system,
            theme: theme,
            onTap: () {
              HapticFeedback.selectionClick();
              ThemeController.setThemeConfig(mode: ThemeMode.system);
            },
          ),
          _buildModeTab(
            label: "Dark",
            icon: Icons.dark_mode_rounded,
            isSelected: currentMode == ThemeMode.dark,
            theme: theme,
            onTap: () {
              HapticFeedback.selectionClick();
              ThemeController.setThemeConfig(mode: ThemeMode.dark);
            },
          ),
          _buildModeTab(
            label: "Light",
            icon: Icons.light_mode_rounded,
            isSelected: currentMode == ThemeMode.light,
            theme: theme,
            onTap: () {
              HapticFeedback.selectionClick();
              ThemeController.setThemeConfig(mode: ThemeMode.light);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required AppTheme theme,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? theme.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? Border.all(color: theme.border) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? theme.textPrimary : theme.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? theme.textPrimary : theme.textMuted,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Accent Color Swatches ──────────────────────────────────────────────────
  Widget _buildAccentPicker(AppTheme theme, AppAccent currentAccent) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: AppAccent.values.map((accent) {
          final isSelected = accent == currentAccent;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ThemeController.setThemeConfig(accent: accent);
              },
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.fillColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? theme.textPrimary : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            color: accent.onAccent(theme.brightness),
                            size: 20,
                          )
                        : null,
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      accent.label,
                      style: TextStyle(
                        color: isSelected ? theme.textPrimary : theme.textMuted,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Live Interactive Preview Mockup ────────────────────────────────────────
  Widget _buildLivePreview(AppTheme theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "PREVIEW",
                style: TextStyle(
                  color: theme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.border),
                  ),
                  child: Text(
                    "${theme.accent.label} • ${isDark ? 'Dark' : 'Light'}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Simulated Chat Container
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Received Bubble
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 240),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.bubblePartner,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                        bottomLeft: Radius.circular(4),
                      ),
                      border: Border.all(color: theme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Are you free this evening?",
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            "10:42",
                            style: TextStyle(
                              color: theme.textMuted,
                              fontSize: 11,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Sent Bubble
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 240),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.bubbleSelf,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Yes! Let's get coffee ☕",
                          style: TextStyle(
                            color: theme.onAccent,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              "10:43",
                              style: TextStyle(
                                color: theme.onAccent.withValues(alpha: 0.75),
                                fontSize: 11,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.done_all_rounded,
                              size: 13,
                              color: theme.onAccent.withValues(alpha: 0.75),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Action Button in preview
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: theme.onAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text("Primary Action Button"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
