import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import '../widgets/passcode_lock_button.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';
import 'passcode_setup_screen.dart';
import 'profile_screen.dart';
import 'security_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Color get bg => ThemeController.currentTheme.value.bg;
  Color get tealCard => ThemeController.currentTheme.value.surfaceTeal;
  Color get rose => ThemeController.currentTheme.value.primary;
  Color get violet => ThemeController.currentTheme.value.secondary;

  String username = "User";
  bool passcodeEnabled = false;
  String? avatarUrl;
  bool fingerprintEnabled = false;
  bool biometricsSupported = false;
  bool darkModeEnabled = true;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccountData();
  }

  Future<void> _loadAccountData() async {
    final userId = await Session.getUserId();
    final usernameSession = await Session.getUsername();
    final hasCode = await SecurityService.hasPasscode();
    final fpEnabled = await SecurityService.isFingerprintEnabled();
    final bioSupport = await SecurityService.isBiometricSupported();

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
        avatarUrl = avUrl;
        passcodeEnabled = hasCode;
        fingerprintEnabled = fpEnabled;
        biometricsSupported = bioSupport;
        isLoading = false;
      });
    }
  }

  void _onTapPasscodeTile() async {
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Local Passcode Options",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.white10,
                  child: Icon(Icons.edit_rounded, color: Colors.white),
                ),
                title: const Text(
                  "Change Passcode",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PasscodeSetupScreen(mode: PasscodeMode.change),
                    ),
                  );
                  if (res == true) _loadAccountData();
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.redAccent.withOpacity(0.2),
                  child: const Icon(Icons.lock_open_rounded, color: Colors.redAccent),
                ),
                title: const Text(
                  "Turn Off Passcode",
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PasscodeSetupScreen(mode: PasscodeMode.disable),
                    ),
                  );
                  if (res == true) _loadAccountData();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _onTapFingerprintTile() async {
    if (!passcodeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enable a Local Passcode first ❤️"),
        ),
      );
      return;
    }

    if (!biometricsSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Biometric authentication is not supported on this device"),
        ),
      );
      return;
    }

    if (fingerprintEnabled) {
      await SecurityService.disableFingerprint();
      _loadAccountData();
    } else {
      final authenticated = await SecurityService.authenticateWithBiometrics(
        reason: "Authenticate to enable Fingerprint / Face unlock ❤️",
      );
      if (authenticated) {
        await SecurityService.enableFingerprint(true);
        _loadAccountData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Biometric authentication failed"),
            ),
          );
        }
      }
    }
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Sign Out", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to sign out of TwoOfUs?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await Session.logout();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text("Sign Out", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
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
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              "Account",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: const [
              PasscodeLockButton(),
              SizedBox(width: 8),
            ],
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // 1. Profile Header
                    _buildProfileHeader(),
                    const SizedBox(height: 16),

                    // 2. Account Tile
                    _buildCard(
                      iconWidget: _gradientIcon(Icons.person_outline_rounded),
                      title: "Account",
                      subtitle: "Profile, privacy, security",
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProfileScreen()),
                        );
                        _loadAccountData();
                      },
                    ),
                const SizedBox(height: 14),

                // 3. Local Passcode Tile
                _buildCard(
                  iconWidget: _gradientIcon(Icons.lock_outline_rounded),
                  title: "Local Passcode",
                  subtitle: passcodeEnabled
                      ? "Enabled • Local PIN protection"
                      : "Set a PIN to lock the app",
                  onTap: _onTapPasscodeTile,
                  trailing: Switch(
                    activeColor: rose,
                    value: passcodeEnabled,
                    onChanged: (_) => _onTapPasscodeTile(),
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Fingerprint / Face ID Tile
                _buildCard(
                  iconWidget: _gradientIcon(Icons.fingerprint_rounded),
                  title: "Fingerprint / Face ID",
                  subtitle: !biometricsSupported
                      ? "Not supported on this device"
                      : (fingerprintEnabled
                          ? "Biometric authentication active"
                          : "Biometric authentication"),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SecurityScreen()),
                    );
                    _loadAccountData();
                  },
                  trailing: Switch(
                    activeColor: rose,
                    value: fingerprintEnabled,
                    onChanged: (_) => _onTapFingerprintTile(),
                  ),
                ),
                const SizedBox(height: 14),

                // 5. Dark Mode Tile
                _buildCard(
                  iconWidget: _gradientIcon(Icons.dark_mode_outlined),
                  title: "Dark Mode",
                  subtitle: darkModeEnabled
                      ? "Dark theme active"
                      : "Enable dark color scheme",
                  onTap: () => setState(() => darkModeEnabled = !darkModeEnabled),
                  trailing: Switch(
                    activeColor: rose,
                    value: darkModeEnabled,
                    onChanged: (val) => setState(() => darkModeEnabled = val),
                  ),
                ),
                const SizedBox(height: 14),

                // 6. Change Password Tile
                _buildCard(
                  iconWidget: _gradientIcon(Icons.shield_outlined),
                  title: "Change Password",
                  subtitle: "Update account password",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                    );
                  },
                ),
                const SizedBox(height: 28),

                // 7. Sign Out Button
                _buildSignOutButton(),
                const SizedBox(height: 20),
              ],
            ),
        );
      },
    );
  }

  Widget _gradientIcon(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [rose, violet],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 22,
      ),
    );
  }

  Widget _buildProfileHeader() {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : "U";

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
        _loadAccountData();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tealCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [rose, violet],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: ClipOval(
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF1E1B2E),
                  ),
                  child: avatarUrl != null && avatarUrl!.isNotEmpty
                      ? Image.network(
                          avatarUrl!.startsWith('http')
                              ? avatarUrl!
                              : "${ApiService.baseUrl}/${avatarUrl!.startsWith('/') ? avatarUrl!.substring(1) : avatarUrl!}",
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        "Tap to edit profile",
                        style: TextStyle(
                          color: rose,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit_outlined,
                        size: 13,
                        color: rose,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white38,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required Widget iconWidget,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: tealCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing,
            ] else ...[
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white38,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSignOutButton() {
    return InkWell(
      onTap: _confirmSignOut,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF191F2B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.redAccent.withOpacity(0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.redAccent.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withOpacity(0.18),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Colors.redAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Sign Out",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    "Log out of TwoOfUs",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.redAccent,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}