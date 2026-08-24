import 'package:flutter/material.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/passcode_lock_button.dart';
import 'passcode_setup_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  Color get bg => ThemeController.currentTheme.value.surfaceTeal;
  Color get surfaceCard => ThemeController.currentTheme.value.surface;
  Color get rose => ThemeController.currentTheme.value.primary;
  Color get violet => ThemeController.currentTheme.value.secondary;

  bool passcodeEnabled = false;
  bool fingerprintEnabled = false;
  bool biometricsSupported = false;
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

    if (mounted) {
      setState(() {
        passcodeEnabled = hasCode;
        fingerprintEnabled = fpEnabled;
        biometricsSupported = bioSupport;
        autoLockDuration = autoLock;
        storageStatus = storageInfo;
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
      if (res == true) _loadSecuritySettings();
    } else {
      _showPasscodeOptions();
    }
  }

  void _showPasscodeOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceCard,
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
                  if (res == true) _loadSecuritySettings();
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
                  if (res == true) _loadSecuritySettings();
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
      _loadSecuritySettings();
    } else {
      final authenticated = await SecurityService.authenticateWithBiometrics(
        reason: "Authenticate to enable Fingerprint / Face unlock ❤️",
      );
      if (authenticated) {
        await SecurityService.enableFingerprint(true);
        _loadSecuritySettings();
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

  void _onTapAutoLockTile() {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final options = [
          {"label": "Immediately", "val": "immediately"},
          {"label": "1 Minute", "val": "1 min"},
          {"label": "5 Minutes", "val": "5 mins"},
          {"label": "15 Minutes", "val": "15 mins"},
          {"label": "Never", "val": "never"},
        ];

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
                "Select Auto Lock Duration",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final isSelected = autoLockDuration == opt["val"];
                return ListTile(
                  title: Text(
                    opt["label"]!,
                    style: TextStyle(
                      color: isSelected ? rose : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: rose)
                      : null,
                  onTap: () async {
                    await SecurityService.setAutoLock(opt["val"]!);
                    if (context.mounted) Navigator.pop(context);
                    _loadSecuritySettings();
                  },
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  String _formatAutoLockDisplay(String raw) {
    switch (raw.toLowerCase()) {
      case "immediately":
        return "Immediately";
      case "1 min":
      case "1 minute":
        return "1 Minute";
      case "5 mins":
      case "5 minutes":
        return "5 Minutes";
      case "15 mins":
      case "15 minutes":
        return "15 Minutes";
      case "never":
        return "Never";
      default:
        return raw.isEmpty ? "Immediately" : raw[0].toUpperCase() + raw.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: activeTheme.surfaceTeal,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              "Security",
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
          ? Center(child: CircularProgressIndicator(color: rose))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  "Protect your private memories ❤️",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),

                // 1. Local Passcode Tile
                _buildCardTile(
                  icon: Icons.lock_outline_rounded,
                  title: "Local Passcode",
                  subtitle: passcodeEnabled
                      ? "Enabled • Local PIN active"
                      : "Disabled • Set a PIN to lock the app",
                  isActive: passcodeEnabled,
                  onTap: _onTapPasscodeTile,
                  trailing: Switch(
                    activeThumbColor: rose,
                    value: passcodeEnabled,
                    onChanged: (_) => _onTapPasscodeTile(),
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Biometric Unlock Tile
                _buildCardTile(
                  icon: Icons.fingerprint_rounded,
                  title: "Biometric Unlock",
                  subtitle: !biometricsSupported
                      ? "Not Available • Hardware not detected"
                      : (fingerprintEnabled
                          ? "Enabled • Biometric unlock active"
                          : "Available • Tap to enable"),
                  isActive: fingerprintEnabled,
                  onTap: _onTapFingerprintTile,
                  trailing: Switch(
                    activeThumbColor: rose,
                    value: fingerprintEnabled,
                    onChanged: (_) => _onTapFingerprintTile(),
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Auto Lock Tile
                _buildCardTile(
                  icon: Icons.timer_outlined,
                  title: "Auto Lock",
                  subtitle: _formatAutoLockDisplay(autoLockDuration),
                  isActive: true,
                  onTap: _onTapAutoLockTile,
                ),
                const SizedBox(height: 14),

                // 4. Encrypted Storage Tile
                _buildCardTile(
                  icon: Icons.shield_outlined,
                  title: "Encrypted Storage",
                  subtitle: "${storageStatus["status"]} • ${storageStatus["detail"]}",
                  isActive: storageStatus["isSecure"] == "true",
                  onTap: () {},
                ),
              ],
            ),
        );
      },
    );
  }

  Widget _buildCardTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: surfaceCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
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
                gradient: LinearGradient(
                  colors: isActive
                      ? [rose, violet]
                      : [Colors.white24, Colors.white12],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 22,
              ),
            ),
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
                      color: isActive ? rose.withOpacity(0.9) : Colors.white54,
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
                color: Colors.white30,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}