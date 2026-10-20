import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — Hardware Passcode & Local PIN Screen
// ─────────────────────────────────────────────────────────────────────────────

enum PasscodeMode { setup, unlock, change, disable }

class PasscodeSetupScreen extends StatefulWidget {
  final PasscodeMode mode;
  final VoidCallback? onSuccess;

  const PasscodeSetupScreen({
    super.key,
    this.mode = PasscodeMode.setup,
    this.onSuccess,
  });

  @override
  State<PasscodeSetupScreen> createState() => _PasscodeSetupScreenState();
}

class _PasscodeSetupScreenState extends State<PasscodeSetupScreen> {
  String passcode = "";
  String tempPasscode = "";

  // Step for multi-step flows (0: initial / current, 1: new, 2: confirm)
  int step = 0;
  String errorMessage = "";
  bool isBiometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == PasscodeMode.unlock) {
      _checkAndTriggerBiometrics();
    }
  }

  Future<void> _checkAndTriggerBiometrics() async {
    final bioEnabled = await SecurityService.isFingerprintEnabled();
    final bioSupported = await SecurityService.isBiometricSupported();
    if (mounted) {
      setState(() {
        isBiometricsAvailable = bioEnabled && bioSupported;
      });
    }

    if (bioEnabled && bioSupported) {
      final authenticated = await SecurityService.authenticateWithBiometrics(
        reason: "Unlock TwoOfUs with Biometrics",
      );
      if (authenticated && mounted) {
        _handleUnlockSuccess();
      }
    }
  }

  void _handleUnlockSuccess() {
    SecurityService.isLocked = false;
    SecurityService.resetInactivityTimer();
    if (widget.onSuccess != null) {
      widget.onSuccess!();
    } else if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop(true);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  String get _titleText {
    switch (widget.mode) {
      case PasscodeMode.setup:
        return step == 0 ? "Create Passcode" : "Confirm Passcode";
      case PasscodeMode.unlock:
        return "TwoOfUs Locked";
      case PasscodeMode.change:
        if (step == 0) return "Current Passcode";
        if (step == 1) return "New Passcode";
        return "Confirm New Passcode";
      case PasscodeMode.disable:
        return "Enter Passcode";
    }
  }

  String get _subtitleText {
    switch (widget.mode) {
      case PasscodeMode.setup:
        return step == 0 ? "Choose a 4-digit PIN for device security" : "Re-enter your 4-digit PIN to confirm";
      case PasscodeMode.unlock:
        return "Enter your 4-digit passcode to unlock";
      case PasscodeMode.change:
        if (step == 0) return "Enter your existing 4-digit PIN";
        if (step == 1) return "Choose a new 4-digit PIN";
        return "Re-enter your new 4-digit PIN";
      case PasscodeMode.disable:
        return "Enter your current PIN to turn off lock";
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        final canGoBack = widget.mode != PasscodeMode.unlock && Navigator.canPop(context);

        return Scaffold(
          backgroundColor: activeTheme.bg,
          appBar: AppBar(
            backgroundColor: activeTheme.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: canGoBack
                ? IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: activeTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
          ),
          body: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 1),

                // Lock Emblem
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: activeTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: activeTheme.border, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.lock_rounded,
                    color: activeTheme.isDark ? activeTheme.accentBright : activeTheme.accentFill,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  _titleText,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: activeTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _subtitleText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: activeTheme.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Error message
                if (errorMessage.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: activeTheme.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: activeTheme.danger.withValues(alpha: 0.4), width: 1),
                    ),
                    child: Text(
                      errorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: activeTheme.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // PIN Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final bool filled = index < passcode.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? (activeTheme.isDark ? activeTheme.accentBright : activeTheme.accentFill)
                            : activeTheme.surfaceRaised,
                        border: Border.all(
                          color: filled
                              ? (activeTheme.isDark ? activeTheme.accentBright : activeTheme.accentFill)
                              : activeTheme.border,
                          width: 1.5,
                        ),
                      ),
                    );
                  }),
                ),

                const Spacer(flex: 2),

                // Numeric Keypad
                _buildKeypad(activeTheme),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKeypad(AppTheme theme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        children: [
          for (var row in [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row.map((digit) => _buildNumberButton(digit, theme)).toList(),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Left: Biometrics or Empty
              if (widget.mode == PasscodeMode.unlock && isBiometricsAvailable)
                _buildActionButton(
                  icon: Icons.fingerprint_rounded,
                  iconColor: theme.isDark ? theme.accentBright : theme.accentFill,
                  theme: theme,
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final auth = await SecurityService.authenticateWithBiometrics();
                    if (auth && mounted) {
                      _handleUnlockSuccess();
                    }
                  },
                )
              else
                const SizedBox(width: 68, height: 68),

              // Center: Zero
              _buildNumberButton("0", theme),

              // Right: Backspace
              _buildActionButton(
                icon: Icons.backspace_outlined,
                iconColor: theme.textSecondary,
                theme: theme,
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (passcode.isNotEmpty) {
                    setState(() {
                      passcode = passcode.substring(0, passcode.length - 1);
                      errorMessage = "";
                    });
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumberButton(String value, AppTheme theme) {
    return InkResponse(
      onTap: () {
        HapticFeedback.lightImpact();
        if (passcode.length >= 4) return;

        setState(() {
          passcode += value;
          errorMessage = "";
        });

        if (passcode.length == 4) {
          Future.delayed(
            const Duration(milliseconds: 140),
            _onCompletedPasscode,
          );
        }
      },
      radius: 34,
      splashColor: theme.accentFill.withValues(alpha: 0.15),
      highlightShape: BoxShape.circle,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.surface,
          border: Border.all(color: theme.border, width: 1),
        ),
        alignment: Alignment.center,
        child: Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            color: theme.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color iconColor,
    required AppTheme theme,
    required VoidCallback onTap,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 34,
      splashColor: theme.accentFill.withValues(alpha: 0.15),
      highlightShape: BoxShape.circle,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.surface,
          border: Border.all(color: theme.border, width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: iconColor, size: 24),
      ),
    );
  }

  Future<void> _onCompletedPasscode() async {
    final code = passcode;
    setState(() {
      passcode = "";
    });

    switch (widget.mode) {
      case PasscodeMode.setup:
        if (step == 0) {
          tempPasscode = code;
          setState(() {
            step = 1;
          });
        } else {
          if (code == tempPasscode) {
            await SecurityService.savePasscode(code);
            if (mounted) {
              AppFeedback.showSuccess(context, "Passcode created successfully");
              Navigator.pop(context, true);
            }
          } else {
            setState(() {
              step = 0;
              tempPasscode = "";
              errorMessage = "Passcodes do not match. Try again.";
            });
            HapticFeedback.mediumImpact();
          }
        }
        break;

      case PasscodeMode.unlock:
        final isValid = await SecurityService.verifyPasscode(code);
        if (mounted) {
          if (isValid) {
            _handleUnlockSuccess();
          } else {
            setState(() {
              errorMessage = "Incorrect passcode";
            });
            HapticFeedback.mediumImpact();
          }
        }
        break;

      case PasscodeMode.change:
        if (step == 0) {
          final isValid = await SecurityService.verifyPasscode(code);
          if (isValid) {
            setState(() {
              step = 1;
            });
          } else {
            setState(() {
              errorMessage = "Current passcode is incorrect";
            });
            HapticFeedback.mediumImpact();
          }
        } else if (step == 1) {
          tempPasscode = code;
          setState(() {
            step = 2;
          });
        } else {
          if (code == tempPasscode) {
            await SecurityService.savePasscode(code);
            if (mounted) {
              AppFeedback.showSuccess(context, "Passcode updated successfully");
              Navigator.pop(context, true);
            }
          } else {
            setState(() {
              step = 1;
              tempPasscode = "";
              errorMessage = "Passcodes do not match. Try again.";
            });
            HapticFeedback.mediumImpact();
          }
        }
        break;

      case PasscodeMode.disable:
        final isValid = await SecurityService.verifyPasscode(code);
        if (mounted) {
          if (isValid) {
            await SecurityService.deletePasscode();
            if (mounted) {
              AppFeedback.showSuccess(context, "Passcode turned off");
              Navigator.pop(context, true);
            }
          } else {
            setState(() {
              errorMessage = "Incorrect passcode";
            });
            HapticFeedback.mediumImpact();
          }
        }
        break;
    }
  }
}