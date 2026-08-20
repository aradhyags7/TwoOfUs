import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/passcode_lock_button.dart';

class ThemeSelectionScreen extends StatefulWidget {
  const ThemeSelectionScreen({super.key});

  @override
  State<ThemeSelectionScreen> createState() => _ThemeSelectionScreenState();
}

class _ThemeSelectionScreenState extends State<ThemeSelectionScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: activeTheme.bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: activeTheme.textPrimary,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  color: activeTheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  "Themes",
                  style: TextStyle(
                    color: activeTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: const [
              PasscodeLockButton(),
              SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              Text(
                "Make TwoOfUs feel like yours.",
                style: TextStyle(
                  color: activeTheme.textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Choose your theme",
                style: TextStyle(
                  color: activeTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              ...AppTheme.allThemes.map((theme) {
                final isSelected = activeTheme.id == theme.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildThemeCard(theme, isSelected),
                );
              }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeCard(AppTheme theme, bool isSelected) {
    return GestureDetector(
      onTap: () {
        ThemeController.setTheme(theme);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? theme.primary : theme.border,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? theme.glow : Colors.black.withOpacity(0.15),
              blurRadius: isSelected ? 16 : 8,
              spreadRadius: isSelected ? 2 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Miniature UI preview box
            Container(
              height: 72,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Mini App bar
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [theme.gradientStart, theme.gradientEnd],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 60,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.textPrimary.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.primary.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  // Mini Chat bubbles preview
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.bubblePartner,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Container(
                          width: 32,
                          height: 5,
                          decoration: BoxDecoration(
                            color: theme.textMuted,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.gradientStart, theme.gradientEnd],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Color Swatches Row
            Row(
              children: [
                _colorDot(theme.bg, "Bg"),
                const SizedBox(width: 6),
                _colorDot(theme.surface, "Surface"),
                const SizedBox(width: 6),
                _colorDot(theme.primary, "Primary"),
                const SizedBox(width: 6),
                _colorDot(theme.secondary, "Secondary"),
              ],
            ),
            const SizedBox(height: 12),
            // Title & Subtitle + Checkmark
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        theme.name,
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        theme.subtitle,
                        style: TextStyle(
                          color: theme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: theme.glow,
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorDot(Color color, String label) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: Colors.white24,
          width: 1,
        ),
      ),
    );
  }
}
