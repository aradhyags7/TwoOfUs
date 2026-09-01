import 'package:flutter/material.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

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
  Color get bg => ThemeController.currentTheme.value.bg;
  Color get surface => ThemeController.currentTheme.value.surface;
  Color get rose => ThemeController.currentTheme.value.primary;
  Color get violet => ThemeController.currentTheme.value.secondary;

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
        reason: "Unlock TwoOfUs with Biometrics ❤️",
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
        return "Welcome Back ❤️";
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
        return step == 0 ? "Choose a 4-digit PIN" : "Re-enter your 4-digit PIN";
      case PasscodeMode.unlock:
        return "Enter your passcode to unlock app";
      case PasscodeMode.change:
        if (step == 0) return "Enter your current PIN";
        if (step == 1) return "Choose a new 4-digit PIN";
        return "Re-enter your new 4-digit PIN";
      case PasscodeMode.disable:
        return "Enter current PIN to disable app lock";
    }
  }

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
        leading: widget.mode == PasscodeMode.unlock
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context, false),
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            children: [
              const SizedBox(height: 10),
              CircleAvatar(
                radius: 40,
                backgroundColor: rose.withOpacity(0.15),
                child: Icon(
                  Icons.lock_rounded,
                  color: rose,
                  size: 44,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _titleText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitleText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                ),
              ),
              if (errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  errorMessage,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  4,
                  (index) {
                    bool filled = index < passcode.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(8),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? rose : Colors.white24,
                        boxShadow: filled
                            ? [
                                BoxShadow(
                                  color: rose.withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            : [],
                      ),
                    );
                  },
                ),
              ),
              const Spacer(),
              _numberPad(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
        );
      },
    );
  }

  Widget _numberPad() {
    return Column(
      children: [
        for (var row in [
          ["1", "2", "3"],
          ["4", "5", "6"],
          ["7", "8", "9"],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map(_button).toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Left slot: Biometrics button if unlocking
            if (widget.mode == PasscodeMode.unlock && isBiometricsAvailable)
              GestureDetector(
                onTap: () async {
                  final auth = await SecurityService.authenticateWithBiometrics();
                  if (auth && mounted) {
                    _handleUnlockSuccess();
                  }
                },
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: surface,
                  child: Icon(
                    Icons.fingerprint_rounded,
                    color: rose,
                    size: 32,
                  ),
                ),
              )
            else
              const SizedBox(width: 68),

            _button("0"),

            // Right slot: Backspace
            GestureDetector(
              onTap: () {
                if (passcode.isNotEmpty) {
                  setState(() {
                    passcode = passcode.substring(0, passcode.length - 1);
                    errorMessage = "";
                  });
                }
              },
              child: CircleAvatar(
                radius: 34,
                backgroundColor: surface,
                child: const Icon(
                  Icons.backspace_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _button(String value) {
    return GestureDetector(
      onTap: () {
        if (passcode.length >= 4) return;

        setState(() {
          passcode += value;
          errorMessage = "";
        });

        if (passcode.length == 4) {
          Future.delayed(
            const Duration(milliseconds: 150),
            _onCompletedPasscode,
          );
        }
      },
      child: CircleAvatar(
        radius: 34,
        backgroundColor: surface,
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Passcode Created ❤️")),
              );
              Navigator.pop(context, true);
            }
          } else {
            setState(() {
              step = 0;
              tempPasscode = "";
              errorMessage = "Passcodes don't match. Try again.";
            });
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Passcode Changed ❤️")),
              );
              Navigator.pop(context, true);
            }
          } else {
            setState(() {
              step = 1;
              tempPasscode = "";
              errorMessage = "Passcodes don't match. Try again.";
            });
          }
        }
        break;

      case PasscodeMode.disable:
        final isValid = await SecurityService.verifyPasscode(code);
        if (isValid) {
          await SecurityService.deletePasscode();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Passcode Removed")),
            );
            Navigator.pop(context, true);
          }
        } else {
          setState(() {
            errorMessage = "Incorrect passcode";
          });
        }
        break;
    }
  }
}