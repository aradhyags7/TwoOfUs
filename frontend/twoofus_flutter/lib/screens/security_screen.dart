import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/passcode_lock_button.dart';
import 'passcode_setup_screen.dart';
import 'two_factor_setup_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — Security & Cryptographic Protection Center
// ─────────────────────────────────────────────────────────────────────────────

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool passcodeEnabled = false;
  bool fingerprintEnabled = false;
  bool biometricsSupported = false;
  bool is2faEnabled = false;
  String twoFactorMethod = "totp";
  int remainingBackupCodes = 0;
  String autoLockDuration = "immediately";
  Map<String, String> storageStatus = {
    "status": "Active",
    "detail": "Hardware KeyStore / Keychain active",
  };
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSecuritySettings();
  }

  Future<void> _loadSecuritySettings() async {
    await SecurityService.refreshPasscodeState();
    final hasCode = await SecurityService.hasPasscode();
    final fpEnabled = await SecurityService.isFingerprintEnabled();
    final bioSupport = await SecurityService.isBiometricSupported();
    final autoLock = await SecurityService.getAutoLock();
    final storageInfo = await SecurityService.getEncryptedStorageStatus();

    bool twoFa = false;
    String method = "totp";
    int backupCount = 0;
    try {
      final twoFaStatus = await ApiService.get2FAStatus();
      if (twoFaStatus != null) {
        twoFa = twoFaStatus["is_2fa_enabled"] == true;
        method = twoFaStatus["two_factor_method"] ?? "totp";
        backupCount = (twoFaStatus["remaining_backup_codes"] ?? 0) as int;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        passcodeEnabled = hasCode;
        fingerprintEnabled = fpEnabled;
        biometricsSupported = bioSupport;
        is2faEnabled = twoFa;
        twoFactorMethod = method;
        remainingBackupCodes = backupCount;
        autoLockDuration = autoLock;
        storageStatus = storageInfo;
        isLoading = false;
      });
    }
  }

  void _onTap2FATile() async {
    HapticFeedback.selectionClick();
    if (!is2faEnabled) {
      final res = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const TwoFactorSetupScreen(),
        ),
      );
      if (res == true) _loadSecuritySettings();
    } else {
      _show2FAOptionsModal();
    }
  }

  void _show2FAOptionsModal() {
    final theme = context.appTheme;

    AppSheet.show(
      context: context,
      builder: (sheetCtx) => AppSheet(
        title: "Two-Factor Authentication",
        subtitle: "Active • ${twoFactorMethod == 'email' ? 'Email OTP' : 'Authenticator App'}",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: theme.success, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "$remainingBackupCodes recovery codes remaining. Keep them safe offline.",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: theme.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AppListTile(
              icon: Icons.refresh_rounded,
              title: "Reconfigure 2FA",
              subtitle: "Generate a new secret or switch method",
              onTap: () async {
                Navigator.pop(sheetCtx);
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TwoFactorSetupScreen(),
                  ),
                );
                if (res == true) _loadSecuritySettings();
              },
            ),
            Divider(height: 1, thickness: 1, color: theme.divider, indent: 56),
            AppListTile(
              icon: Icons.no_encryption_rounded,
              title: "Disable Two-Factor Auth",
              subtitle: "Requires account password verification",
              isDestructive: true,
              onTap: () {
                Navigator.pop(sheetCtx);
                _showDisable2FADialog();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showDisable2FADialog() {
    final passCtrl = TextEditingController();
    bool isDisabling = false;

    AppSheet.show(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AppSheet(
          title: "Disable Two-Factor Auth",
          subtitle: "Confirm your account master password",
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: passCtrl,
                isPassword: true,
                label: "Account Password",
                hintText: "Enter your password to verify",
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: "Cancel",
                      variant: AppButtonVariant.secondary,
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      text: "Disable",
                      variant: AppButtonVariant.danger,
                      isLoading: isDisabling,
                      onPressed: isDisabling
                          ? null
                          : () async {
                              final pass = passCtrl.text.trim();
                              if (pass.isEmpty) return;
                              setDlgState(() => isDisabling = true);
                              final res = await ApiService.disable2FA(password: pass);
                              if (!mounted) return;
                              if (res != null && res["success"] == true) {
                                Navigator.pop(sheetCtx);
                                AppFeedback.showSuccess(context, "Two-Factor Authentication disabled");
                                _loadSecuritySettings();
                              } else {
                                setDlgState(() => isDisabling = false);
                                AppFeedback.showError(context, res?["error"] ?? "Invalid password.");
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _onTapPasscodeTile() async {
    HapticFeedback.selectionClick();
    if (!passcodeEnabled) {
      final res = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PasscodeSetupScreen(mode: PasscodeMode.setup),
        ),
      );
      if (res == true) _loadSecuritySettings();
    } else {
      _showPasscodeOptions();
    }
  }

  void _showPasscodeOptions() {
    final theme = context.appTheme;

    AppSheet.show(
      context: context,
      builder: (sheetCtx) => AppSheet(
        title: "Local Passcode Options",
        subtitle: "Manage device PIN security",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppListTile(
              icon: Icons.edit_rounded,
              title: "Change Passcode",
              subtitle: "Enter current PIN to set a new one",
              onTap: () async {
                Navigator.pop(sheetCtx);
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PasscodeSetupScreen(mode: PasscodeMode.change),
                  ),
                );
                if (res == true) _loadSecuritySettings();
              },
            ),
            Divider(height: 1, thickness: 1, color: theme.divider, indent: 56),
            AppListTile(
              icon: Icons.lock_open_rounded,
              title: "Turn Off Passcode",
              subtitle: "Remove local device PIN requirement",
              isDestructive: true,
              onTap: () async {
                Navigator.pop(sheetCtx);
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PasscodeSetupScreen(mode: PasscodeMode.disable),
                  ),
                );
                if (res == true) _loadSecuritySettings();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _onTapFingerprintTile() async {
    HapticFeedback.selectionClick();
    if (!passcodeEnabled) {
      AppFeedback.showInfo(
        context,
        "Please enable a local passcode first",
      );
      return;
    }

    if (!biometricsSupported) {
      AppFeedback.showInfo(
        context,
        "Biometric authentication is not supported on this device",
      );
      return;
    }

    if (fingerprintEnabled) {
      await SecurityService.disableFingerprint();
      _loadSecuritySettings();
    } else {
      final authenticated = await SecurityService.authenticateWithBiometrics(
        reason: "Authenticate to enable Biometric unlock",
      );
      if (authenticated) {
        await SecurityService.enableFingerprint(true);
        _loadSecuritySettings();
      } else {
        if (mounted) {
          AppFeedback.showError(
            context,
            "Biometric authentication failed",
          );
        }
      }
    }
  }

  void _onTapAutoLockTile() {
    HapticFeedback.selectionClick();
    final theme = context.appTheme;

    final options = [
      {"label": "Immediately", "val": "immediately"},
      {"label": "1 Minute", "val": "1 min"},
      {"label": "5 Minutes", "val": "5 mins"},
      {"label": "15 Minutes", "val": "15 mins"},
      {"label": "Never", "val": "never"},
    ];

    AppSheet.show(
      context: context,
      builder: (sheetCtx) => AppSheet(
        title: "Auto-Lock Duration",
        subtitle: "Lock the app when moved to background",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...options.map((opt) {
              final isSelected = autoLockDuration == opt["val"];
              return AppListTile(
                icon: Icons.timer_outlined,
                title: opt["label"]!,
                trailing: isSelected
                    ? Icon(Icons.check_circle_rounded, color: theme.isDark ? theme.accentBright : theme.accentFill)
                    : null,
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await SecurityService.setAutoLock(opt["val"]!);
                  _loadSecuritySettings();
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _formatAutoLockDisplay(String val) {
    switch (val) {
      case "immediately":
        return "Immediately on background";
      case "1 min":
        return "After 1 minute";
      case "5 mins":
        return "After 5 minutes";
      case "15 mins":
        return "After 15 minutes";
      case "never":
        return "Never";
      default:
        return val;
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
            backgroundColor: activeTheme.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              "Security Center",
              style: TextStyle(
                fontFamily: 'Inter',
                color: activeTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            actions: const [
              PasscodeLockButton(),
              SizedBox(width: 12),
            ],
          ),
          body: isLoading
              ? Center(child: CircularProgressIndicator(color: activeTheme.accentFill))
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    // Section 1: Device Access Protection
                    SectionGroup(
                      title: "Device Lock",
                      footer: "Requires authentication whenever TwoOfUs is launched or resumed.",
                      children: [
                        AppListTile(
                          icon: Icons.lock_outline_rounded,
                          title: "Local Passcode",
                          subtitle: passcodeEnabled
                              ? "Enabled • 4-digit PIN lock"
                              : "Disabled • Require PIN on launch",
                          trailing: Switch(
                            activeThumbColor: activeTheme.accentFill,
                            value: passcodeEnabled,
                            onChanged: (_) => _onTapPasscodeTile(),
                          ),
                          onTap: _onTapPasscodeTile,
                        ),
                        AppListTile(
                          icon: Icons.fingerprint_rounded,
                          title: "Biometric Unlock",
                          subtitle: !biometricsSupported
                              ? "Hardware not detected"
                              : (fingerprintEnabled
                                  ? "Enabled • Face / Fingerprint active"
                                  : "Available • Fast authentication"),
                          trailing: Switch(
                            activeThumbColor: activeTheme.accentFill,
                            value: fingerprintEnabled,
                            onChanged: (_) => _onTapFingerprintTile(),
                          ),
                          onTap: _onTapFingerprintTile,
                        ),
                        AppListTile(
                          icon: Icons.timer_outlined,
                          title: "Auto-Lock",
                          subtitle: _formatAutoLockDisplay(autoLockDuration),
                          showChevron: true,
                          onTap: _onTapAutoLockTile,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Section 2: Account Multi-Factor Authentication
                    SectionGroup(
                      title: "Account Authentication",
                      footer: "Adds a second layer of verification during sign-in on any new device.",
                      children: [
                        AppListTile(
                          icon: Icons.shield_outlined,
                          title: "Two-Factor Auth (2FA)",
                          subtitle: is2faEnabled
                              ? "Active • ${twoFactorMethod == 'email' ? 'Email OTP' : 'Authenticator App'}"
                              : "Disabled • Protect login with Authenticator or Email",
                          trailing: Switch(
                            activeThumbColor: activeTheme.accentFill,
                            value: is2faEnabled,
                            onChanged: (_) => _onTap2FATile(),
                          ),
                          onTap: _onTap2FATile,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Section 3: Encrypted Storage Architecture
                    SectionGroup(
                      title: "Cryptographic Storage",
                      footer: "Zero-knowledge encryption keys never leave this device unencrypted.",
                      children: [
                        AppListTile(
                          icon: Icons.verified_user_outlined,
                          title: "Hardware Keystore",
                          subtitle: "${storageStatus["status"]} • ${storageStatus["detail"]}",
                        ),
                        const AppListTile(
                          icon: Icons.key_rounded,
                          title: "Double Ratchet E2EE",
                          subtitle: "Curve25519 & XChaCha20-Poly1305 active",
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
        );
      },
    );
  }
}