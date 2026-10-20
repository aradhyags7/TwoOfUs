import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../utils/session.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/passcode_lock_button.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';
import 'passcode_setup_screen.dart';
import 'profile_screen.dart';
import 'security_screen.dart';
import 'theme_selection_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — Professional Account & Settings Screen
// ─────────────────────────────────────────────────────────────────────────────

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String username = "User";
  String? email;
  String? avatarUrl;
  bool passcodeEnabled = false;
  bool fingerprintEnabled = false;
  bool biometricsSupported = false;
  bool is2faEnabled = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccountData();
  }

  Future<void> _loadAccountData() async {
    final userId = await Session.getUserId();
    final usernameSession = await Session.getUsername();
    final userEmail = await Session.getEmail();
    final hasCode = await SecurityService.hasPasscode();
    final fpEnabled = await SecurityService.isFingerprintEnabled();
    final bioSupport = await SecurityService.isBiometricSupported();
    final twoFactorStatus = await ApiService.get2FAStatus();

    String name = usernameSession ?? "";
    String? avUrl;
    if (userId != null) {
      final profile = await ApiService.getProfile(userId);
      if (profile != null) {
        if (profile["username"] != null && name.isEmpty) {
          name = profile["username"];
        }
        avUrl = profile["avatar_url"];
      }
    }

    if (mounted) {
      setState(() {
        username = name.isNotEmpty ? name : "User";
        email = userEmail;
        avatarUrl = avUrl;
        passcodeEnabled = hasCode;
        fingerprintEnabled = fpEnabled;
        biometricsSupported = bioSupport;
        is2faEnabled = twoFactorStatus?["enabled"] == true;
        isLoading = false;
      });
    }
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
      if (res == true) _loadAccountData();
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
        subtitle: "Manage your device PIN lock",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppListTile(
              icon: Icons.edit_rounded,
              title: "Change Passcode",
              subtitle: "Set a new 4-digit PIN",
              onTap: () async {
                Navigator.pop(sheetCtx);
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PasscodeSetupScreen(mode: PasscodeMode.change),
                  ),
                );
                if (res == true) _loadAccountData();
              },
            ),
            Divider(height: 1, thickness: 1, color: theme.divider, indent: 56),
            AppListTile(
              icon: Icons.lock_open_rounded,
              title: "Turn Off Passcode",
              subtitle: "Disable local PIN protection",
              isDestructive: true,
              onTap: () async {
                Navigator.pop(sheetCtx);
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PasscodeSetupScreen(mode: PasscodeMode.disable),
                  ),
                );
                if (res == true) _loadAccountData();
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
      _loadAccountData();
    } else {
      final authenticated = await SecurityService.authenticateWithBiometrics(
        reason: "Authenticate to enable Biometric unlock",
      );
      if (authenticated) {
        await SecurityService.enableFingerprint(true);
        _loadAccountData();
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

  void _confirmSignOut() {
    HapticFeedback.mediumImpact();
    final theme = context.appTheme;

    AppSheet.show(
      context: context,
      builder: (sheetCtx) => AppSheet(
        title: "Sign Out",
        subtitle: "Are you sure you want to sign out of TwoOfUs?",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: theme.danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Local sessions will be cleared. You will need your password to log in again.",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: theme.danger,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
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
                    text: "Sign Out",
                    variant: AppButtonVariant.danger,
                    onPressed: () async {
                      Navigator.pop(sheetCtx);
                      await Session.logout();
                      if (mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
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
    );
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
              "Account & Settings",
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
                    // 1. Profile Hero Card
                    _buildProfileHero(activeTheme),
                    const SizedBox(height: 16),

                    // 2. Security Section
                    SectionGroup(
                      title: "Security & Privacy",
                      footer: "Hardware-backed biometric lock & end-to-end encrypted storage.",
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
                          icon: Icons.shield_outlined,
                          title: "Security Center",
                          subtitle: is2faEnabled ? "2FA Active • Storage Protection" : "2FA & Storage Settings",
                          showChevron: true,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SecurityScreen()),
                            );
                            _loadAccountData();
                          },
                        ),
                        AppListTile(
                          icon: Icons.key_rounded,
                          title: "Change Password",
                          subtitle: "Update account master password",
                          showChevron: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // 3. Preferences Section
                    SectionGroup(
                      title: "Appearance",
                      children: [
                        AppListTile(
                          icon: Icons.palette_outlined,
                          title: "Theme & Accents",
                          subtitle: "${activeTheme.name} • ${activeTheme.accent.name}",
                          showChevron: true,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ThemeSelectionScreen()),
                            );
                            _loadAccountData();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // 4. Session & Sign Out Section
                    SectionGroup(
                      title: "Session",
                      children: [
                        AppListTile(
                          icon: Icons.logout_rounded,
                          title: "Sign Out",
                          subtitle: "Log out of TwoOfUs on this device",
                          isDestructive: true,
                          showChevron: true,
                          onTap: _confirmSignOut,
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

  Widget _buildProfileHero(AppTheme theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border, width: 1),
      ),
      child: Row(
        children: [
          AppAvatar(
            name: username,
            imageUrl: avatarUrl != null && avatarUrl!.isNotEmpty
                ? (avatarUrl!.startsWith('http')
                    ? avatarUrl
                    : "${ApiService.baseUrl}/${avatarUrl!.startsWith('/') ? avatarUrl!.substring(1) : avatarUrl!}")
                : null,
            size: 58,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (email != null && email!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email!,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: theme.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.accentFill.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.accentFill.withValues(alpha: 0.3), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded, size: 10, color: theme.isDark ? theme.accentBright : theme.accentFill),
                          const SizedBox(width: 4),
                          Text(
                            "E2EE ACTIVE",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: theme.isDark ? theme.accentBright : theme.accentFill,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, color: theme.textSecondary, size: 20),
            tooltip: "Edit Profile",
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              _loadAccountData();
            },
          ),
        ],
      ),
    );
  }
}