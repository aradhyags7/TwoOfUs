import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../utils/session.dart';
import '../widgets/passcode_lock_button.dart';
import 'login_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'partner_profile_screen.dart';
import 'theme_selection_screen.dart';
import 'security_screen.dart';
import '../services/call_service.dart';
import 'media_gallery_screen.dart';
import '../widgets/qr_scanner_dialog.dart';
import '../widgets/design_system/design_system.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — HomeScreen
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _pinController = TextEditingController();

  // ── User Profile State ─────────────────────────────────────────────────────
  int? _userId;
  String _username = "My Profile";
  String _userEmail = "";
  String? _userBio;
  String? _userAvatarUrl;
  int _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;

  // ── Partner State ──────────────────────────────────────────────────────────
  bool _isPartnerConnected = false;
  int? _partnerId;
  String _partnerName = "";
  String _generatedPin = "";
  int _connectTab = 0; // 0 = Enter PIN  |  1 = Scan QR
  bool _pinCopied = false;
  bool _isConnecting = false;

  // ── Active Real-Time Pairing Polling ───────────────────────────────────────
  Timer? _pairingPollTimer;
  bool _hasTriggeredCelebration = false;

  String? get _resolvedAvatarUrl => _userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
      ? (_userAvatarUrl!.startsWith('http')
          ? "${_userAvatarUrl!}?v=$_avatarCacheKey"
          : "${ApiService.baseUrl}/${_userAvatarUrl!.startsWith('/') ? _userAvatarUrl!.substring(1) : _userAvatarUrl!}?v=$_avatarCacheKey")
      : null;

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _heartCtrl;
  late Animation<double> _heartScale;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── Palette (Reacts to ThemeController) ────────────────────────────────────
  AppTheme get _theme => ThemeController.currentTheme.value;
  Color get _bg => _theme.bg;
  Color get _surface => _theme.surface;
  Color get _rose => _theme.primary;
  Color get _violet => _theme.secondary;
  Color get _text => _theme.textPrimary;
  Color get _sub => _theme.textMuted;
  Color get _border => _theme.border;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _heartScale = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _heartCtrl, curve: Curves.easeInOut),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.78, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _startPairingPolling();
    CallService.startIncomingCallWatcher(context);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadAllData();
    });
  }

  @override
  void dispose() {
    _pairingPollTimer?.cancel();
    _pinController.dispose();
    _heartCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Data Fetching ──────────────────────────────────────────────────────────
  Future<void> _loadAllData() async {
    await Future.wait([
      _loadUserProfile(),
      _loadPartnerStatus(),
      _generatePin(silent: true),
    ]);
  }

  Future<void> _loadUserProfile() async {
    try {
      final userId = await Session.getUserId();
      final username = await Session.getUsername();
      final email = await Session.getEmail();

      if (userId != null && mounted) {
        setState(() {
          _userId = userId;
          _username = username ?? "My Profile";
          _userEmail = email ?? "";
        });

        final profile = await ApiService.getProfile(userId);
        if (profile != null && mounted) {
          setState(() {
            _username = profile["username"] ?? _username;
            _userEmail = profile["email"] ?? _userEmail;
            _userBio = profile["bio"];
            _userAvatarUrl = profile["avatar_url"];
            _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;
          });
        }
      }
    } catch (_) {}
  }

  void _startPairingPolling() {
    _pairingPollTimer?.cancel();
    _pairingPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (!mounted || _isPartnerConnected || _hasTriggeredCelebration) {
        _pairingPollTimer?.cancel();
        return;
      }
      await _checkPartnerStatusLive();
    });
  }

  Future<void> _checkPartnerStatusLive() async {
    try {
      final userId = await Session.getUserId();
      final token = await Session.getToken();
      if (userId == null) return;

      final result = await ApiService.getPairStatus(userId, token: token);
      if (result != null && mounted) {
        final connected = result["connected"] == true;
        final partnerId = result["partner_id"] as int?;
        final partnerName = (result["partner_name"] ?? "Partner").toString();

        if (connected && partnerId != null && !_hasTriggeredCelebration) {
          _pairingPollTimer?.cancel();
          _hasTriggeredCelebration = true;

          setState(() {
            _isPartnerConnected = true;
            _partnerId = partnerId;
            _partnerName = partnerName;
          });

          await Session.savePartner(partnerId, partnerName.isNotEmpty ? partnerName : "Partner");

          if (mounted) {
            _showConnectedCelebrationModal(partnerId, partnerName.isNotEmpty ? partnerName : "Partner");
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadPartnerStatus({bool autoNavigate = true}) async {
    try {
      final userId = await Session.getUserId();
      final token = await Session.getToken();
      if (userId == null) return;

      final result = await ApiService.getPairStatus(userId, token: token);
      if (result != null && mounted) {
        final connected = result["connected"] == true;
        final partnerId = result["partner_id"] as int?;
        final partnerName = (result["partner_name"] ?? "").toString();

        setState(() {
          _isPartnerConnected = connected;
          _partnerId = partnerId;
          _partnerName = partnerName;
        });

        // If user is connected to a partner, save partner cache and directly navigate to ChatScreen
        if (connected && partnerId != null) {
          _pairingPollTimer?.cancel();
          await Session.savePartner(partnerId, partnerName.isNotEmpty ? partnerName : "Partner");
          if (autoNavigate && mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  partnerId: partnerId,
                  partnerName: partnerName.isNotEmpty ? partnerName : "Partner",
                ),
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  void _showConnectedCelebrationModal(int partnerId, String partnerName) {
    if (!mounted) return;
    _pairingPollTimer?.cancel();
    _hasTriggeredCelebration = true;

    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.mediumImpact());
    Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.selectionClick());

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Connected",
      barrierColor: Colors.black.withValues(alpha: 0.82),
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (dialogContext, anim1, anim2) {
        return _ConnectedCelebrationDialog(
          partnerName: partnerName,
          userName: _username,
          onEnter: () {
            Navigator.of(dialogContext, rootNavigator: true).pop();
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 500),
                pageBuilder: (c, animation, secondaryAnimation) => ChatScreen(
                  partnerId: partnerId,
                  partnerName: partnerName,
                ),
                transitionsBuilder: (_, animation, secondaryAnimation, child) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.04),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                      child: child,
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _generatePin({bool silent = false}) async {
    try {
      final userId = await Session.getUserId();
      final token = await Session.getToken();
      if (userId == null) return;

      final result = await ApiService.generatePin(userId, token: token);
      if (result != null && mounted) {
        setState(() => _generatedPin = result["pin"] ?? "");
        if (!silent) _toast("New pairing PIN generated");
      }
    } catch (_) {}
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  void _copyPin() {
    if (_generatedPin.isEmpty) return;
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _generatedPin));
    setState(() => _pinCopied = true);
    _toast("PIN copied to clipboard 📋");
    Future.delayed(
      const Duration(seconds: 2),
      () => mounted ? setState(() => _pinCopied = false) : null,
    );
  }

  Future<void> _connectWithPin([String? explicitPin]) async {
    final rawInput = (explicitPin ?? _pinController.text).trim().toUpperCase();
    final pin = rawInput.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (pin.length != 8) {
      _toast("Please enter your partner's 8-digit PIN", isError: true);
      return;
    }

    final userId = await Session.getUserId();
    final token = await Session.getToken();
    if (userId == null) {
      _toast("Please log in again", isError: true);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isConnecting = true);

    final result = await ApiService.connectByPin(userId, pin, token: token);
    if (!mounted) return;

    setState(() => _isConnecting = false);

    if (result != null) {
      _pinController.clear();
      _pairingPollTimer?.cancel();
      _hasTriggeredCelebration = true;

      final partnerId = result["partner_id"] as int?;
      final partnerName = (result["partner_name"] ?? "Partner").toString();

      if (partnerId != null) {
        setState(() {
          _isPartnerConnected = true;
          _partnerId = partnerId;
          _partnerName = partnerName;
        });

        await Session.savePartner(partnerId, partnerName);
        _showConnectedCelebrationModal(partnerId, partnerName);
      } else {
        await _loadPartnerStatus(autoNavigate: true);
      }
    } else {
      _toast("Invalid PIN or connection failed. Please check and try again.", isError: true);
    }
  }

  Future<void> _scanPartnerQR() async {
    HapticFeedback.lightImpact();
    final scannedCode = await QRScannerDialog.scan(
      context,
      partnerName: "Partner",
      title: "Scan Partner QR",
      subtitle: "Point camera at your partner's QR code on their screen, or upload a saved QR screenshot.",
    );

    if (scannedCode == null || scannedCode.trim().isEmpty || !mounted) return;

    await _processScannedPairData(scannedCode.trim());
  }

  Future<void> _processScannedPairData(String rawCode) async {
    String pin = rawCode.trim();

    // 1. Try URI query parameter (twoofus://pair?pin=QOTP-2BSL or https://...pin=...)
    if (pin.contains("pin=")) {
      final uri = Uri.tryParse(pin);
      if (uri != null && uri.queryParameters.containsKey("pin")) {
        pin = uri.queryParameters["pin"]!;
      } else {
        final match = RegExp(r'pin=([A-Za-z0-9\-]+)').firstMatch(pin);
        if (match != null) {
          pin = match.group(1)!;
        }
      }
    }

    // 2. Normalize and strip non-alphanumeric chars
    final cleanPin = pin.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

    if (cleanPin.length != 8) {
      _toast("Scanned QR does not contain a valid 8-character PIN", isError: true);
      return;
    }

    _pinController.text = cleanPin;
    _toast("QR Scanned: $cleanPin! Connecting...", isError: false);
    await _connectWithPin(cleanPin);
  }

  void _toast(String msg, {bool isError = false}) {
    if (isError) {
      AppFeedback.showError(context, msg);
    } else {
      AppFeedback.showSuccess(context, msg);
    }
  }

  void _openProfileScreen() async {
    HapticFeedback.lightImpact();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (mounted) {
      _loadUserProfile();
    }
  }

  void _openThemeSelectionScreen() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ThemeSelectionScreen()),
    );
  }

  void _openChatScreen() {
    if (_partnerId == null) {
      _toast("Partner not connected yet", isError: true);
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          partnerId: _partnerId!,
          partnerName: _partnerName.isNotEmpty ? _partnerName : "Partner",
        ),
      ),
    );
  }

  void _openPartnerProfile() {
    if (_partnerId == null) return;
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PartnerProfileScreen(
          partnerId: _partnerId!,
          partnerName: _partnerName.isNotEmpty ? _partnerName : "Partner",
        ),
      ),
    );
  }

  void _openMediaVault() async {
    if (_partnerId == null) return;
    final token = await Session.getToken() ?? '';
    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaGalleryScreen(
          partnerId: _partnerId!,
          partnerName: _partnerName.isNotEmpty ? _partnerName : "Partner",
          token: token,
        ),
      ),
    );
  }

  void _openSecurityScreen() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SecurityScreen()),
    );
  }

  void _showLogoutDialog() {
    HapticFeedback.mediumImpact();
    AppSheet.show(
      context: context,
      builder: (ctx) => AppSheet(
        title: "Sign Out",
        subtitle: "Are you sure you want to sign out of TwoOfUs?",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            AppButton(
              text: "Sign out",
              variant: AppButtonVariant.danger,
              isFullWidth: true,
              onPressed: () async {
                Navigator.pop(ctx);
                await Session.clear();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
            const SizedBox(height: 10),
            AppButton(
              text: "Cancel",
              variant: AppButtonVariant.secondary,
              isFullWidth: true,
              onPressed: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: [


              // ── Main Content ───────────────────────────────────────────────
              SafeArea(
                child: Column(
                  children: [
                    _buildAppBar(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadAllData,
                        color: _rose,
                        backgroundColor: _surface,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── 1. User Profile Card ───────────────────────
                              _buildUserProfileBanner(),
                              const SizedBox(height: 20),

                              // ── 2. Theme Switcher Strip ────────────────────
                              _buildQuickThemeStrip(),
                              const SizedBox(height: 24),

                              // ── 3. Connected Space OR Pairing ───────────────
                              if (_isPartnerConnected) ...[
                                _buildConnectedSpaceHero(),
                              ] else ...[
                                _buildStatusCard(),
                                const SizedBox(height: 26),
                                _buildSectionLabel("Share Connection Code"),
                                const SizedBox(height: 12),
                                _buildShareSection(),
                                const SizedBox(height: 26),
                                _buildSectionLabel("Enter Connection Code"),
                                const SizedBox(height: 12),
                                _buildConnectTabs(),
                                const SizedBox(height: 12),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  transitionBuilder: (child, anim) => FadeTransition(
                                    opacity: anim,
                                    child: child,
                                  ),
                                  child: _buildTabContent(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Icon(Icons.all_inclusive_rounded, size: 26, color: _rose),
          const SizedBox(width: 10),
          Text(
            "TwoOfUs",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _text,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),

          // ── Themes Button ──────────────────────────────────────────────────
          IconButton(
            tooltip: "Customize Themes",
            onPressed: _openThemeSelectionScreen,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _surface,
                border: Border.all(color: _border),
              ),
              child: Icon(Icons.palette_outlined, size: 18, color: _rose),
            ),
          ),

          // ── Passcode Lock Button ───────────────────────────────────────────
          const PasscodeLockButton(),
          const SizedBox(width: 4),

          // ── Profile Avatar Mini-Button ─────────────────────────────────────
          GestureDetector(
            onTap: _openProfileScreen,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: AppAvatar(
                size: 38,
                name: _username,
                imageUrl: _resolvedAvatarUrl,
              ),
            ),
          ),

          // ── Logout Button ──────────────────────────────────────────────────
          IconButton(
            tooltip: "Sign out",
            onPressed: _showLogoutDialog,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _surface,
                border: Border.all(color: _border),
              ),
              child: Icon(Icons.logout_rounded, size: 18, color: _sub),
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. User Profile Banner ─────────────────────────────────────────────────
  Widget _buildUserProfileBanner() {
    return GestureDetector(
      onTap: _openProfileScreen,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            AppAvatar(
              size: 56,
              name: _username,
              imageUrl: _resolvedAvatarUrl,
            ),
            const SizedBox(width: 14),

            // Profile info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _username,
                          style: TextStyle(
                            color: _text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _theme.accentFill.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _theme.accentFill.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          "You",
                          style: TextStyle(
                            color: _theme.accentBright,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userBio != null && _userBio!.isNotEmpty
                        ? _userBio!
                        : (_userEmail.isNotEmpty ? _userEmail : "Tap to complete your profile bio"),
                    style: TextStyle(
                      color: _sub,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: _sub,
            ),
          ],
        ),
      ),
    );
  }

  // ── 2. Quick Theme Selector Strip ──────────────────────────────────────────
  Widget _buildQuickThemeStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionLabel("App Atmosphere"),
            GestureDetector(
              onTap: _openThemeSelectionScreen,
              child: Row(
                children: [
                  Text(
                    "All Themes",
                    style: TextStyle(
                      color: _rose,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.arrow_forward_ios_rounded, size: 11, color: _rose),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: AppTheme.allThemes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final itemTheme = AppTheme.allThemes[index];
              final isSelected = itemTheme.id == _theme.id;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ThemeController.setTheme(itemTheme);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? itemTheme.primary : _border,
                      width: isSelected ? 1.8 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: itemTheme.primary.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    children: [
                      // Gradient Color Swatch Orb
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [itemTheme.primary, itemTheme.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: itemTheme.primary.withValues(alpha: 0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemTheme.name,
                            style: TextStyle(
                              color: isSelected ? itemTheme.primary : _text,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                          Text(
                            itemTheme.subtitle,
                            style: TextStyle(
                              color: _sub,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── 3. Connected Space ──────────────────────────────────────────────────────
  Widget _buildConnectedSpaceHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("Connected Space"),
        const SizedBox(height: 12),

        // Connected Visual Card
        AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              colors: [
                _violet.withValues(alpha: 0.28),
                _rose.withValues(alpha: 0.16),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _rose.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: _rose.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Two Avatars + Connection Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // User Avatar
                  Column(
                    children: [
                      AppAvatar(
                        size: 64,
                        name: _username,
                        imageUrl: _resolvedAvatarUrl,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _username,
                        style: TextStyle(
                          color: _text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  // Secure Connection Link
                  Expanded(
                    child: Column(
                      children: [
                        ScaleTransition(
                          scale: _heartScale,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [_rose, _violet]),
                              boxShadow: [
                                BoxShadow(
                                  color: _rose.withValues(alpha: 0.45),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.link_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "E2EE Active",
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Partner Avatar
                  Column(
                    children: [
                      GestureDetector(
                        onTap: _openPartnerProfile,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AppAvatar(
                              size: 64,
                              name: _partnerName.isNotEmpty ? _partnerName : "Partner",
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: AnimatedBuilder(
                                animation: _pulseAnim,
                                builder: (_, _) => Transform.scale(
                                  scale: _pulseAnim.value,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.greenAccent,
                                      border: Border.all(color: _surface, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.greenAccent.withValues(alpha: 0.6),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _partnerName.isNotEmpty ? _partnerName : "Partner",
                        style: TextStyle(
                          color: _text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Open Private Chat CTA
              AppButton(
                text: "Open Private Chat",
                icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                isFullWidth: true,
                onPressed: _openChatScreen,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Quick Navigation Grid
        Row(
          children: [
            Expanded(
              child: _buildQuickActionTile(
                icon: Icons.person_outline_rounded,
                label: _partnerName.isNotEmpty ? _partnerName : "Profile",
                onTap: _openPartnerProfile,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionTile(
                icon: Icons.photo_library_outlined,
                label: "Media Vault",
                onTap: _openMediaVault,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionTile(
                icon: Icons.security_rounded,
                label: "Security & Lock",
                onTap: _openSecurityScreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionTile(
                icon: Icons.palette_outlined,
                label: "Theme & Mood",
                onTap: _openThemeSelectionScreen,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _rose.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: _rose),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: _text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Unconnected Status Card ────────────────────────────────────────────────
  Widget _buildStatusCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            _violet.withValues(alpha: 0.22),
            _rose.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: _border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.grey.shade700, Colors.grey.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.person_off_outlined,
              color: Colors.white70,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Connection Status",
                style: TextStyle(color: _sub, fontSize: 12, letterSpacing: 0.3),
              ),
              const SizedBox(height: 4),
              Text(
                "Not Connected",
                style: TextStyle(
                  color: _rose,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _rose.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _rose.withValues(alpha: 0.3)),
            ),
            child: Text(
              "Connect",
              style: TextStyle(
                color: _rose,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Share Section: Side-by-side QR & PIN ───────────────────────────────────
  void _showPairingQRModal() {
    HapticFeedback.lightImpact();
    final pairPayload = "twoofus://pair?pin=$_generatedPin&uid=${_userId ?? 0}&name=${Uri.encodeComponent(_username)}";
    AppSheet.show(
      context: context,
      builder: (ctx) => AppSheet(
        title: "Connection QR Code",
        subtitle: "Scan this code to connect instantly",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _rose.withValues(alpha: 0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: QrImageView(
                data: pairPayload,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF13111C)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF13111C)),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _rose.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _rose.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pin_rounded, size: 16, color: _rose),
                  const SizedBox(width: 8),
                  Text(
                    "PIN: ${_generatedPin.isNotEmpty ? _generatedPin : '----'}",
                    style: TextStyle(color: _rose, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AppButton(
              text: "Copy PIN to Share",
              icon: const Icon(Icons.copy_rounded, size: 18),
              isFullWidth: true,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _generatedPin));
                HapticFeedback.lightImpact();
                Navigator.pop(ctx);
                _toast("Invite PIN copied to clipboard");
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareSection() {
    final pairPayload = "twoofus://pair?pin=$_generatedPin&uid=${_userId ?? 0}&name=${Uri.encodeComponent(_username)}";

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // QR Card
          Expanded(
            child: _buildCard(
              child: Column(
                children: [
                  Text(
                    "Your QR",
                    style: TextStyle(
                      color: _text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _showPairingQRModal,
                    child: Container(
                      width: double.infinity,
                      height: 118,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white,
                        border: Border.all(color: _rose.withValues(alpha: 0.28)),
                        boxShadow: [
                          BoxShadow(
                            color: _rose.withValues(alpha: 0.15),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Center(
                        child: QrImageView(
                          data: pairPayload,
                          version: QrVersions.auto,
                          size: 100,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF13111C)),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF13111C)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppButton(
                    text: "View QR",
                    icon: const Icon(Icons.fullscreen_rounded, size: 16),
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    isFullWidth: true,
                    onPressed: _showPairingQRModal,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // PIN Card
          Expanded(
            child: _buildCard(
              child: Column(
                children: [
                  Text(
                    "Share PIN",
                    style: TextStyle(
                      color: _text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 118,
                    child: Center(
                      child: _generatedPin.isNotEmpty
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _generatedPin.length == 8
                                      ? '${_generatedPin.substring(0, 4)}-${_generatedPin.substring(4, 8)}'
                                      : _generatedPin,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2,
                                    color: _rose,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                GestureDetector(
                                  onTap: _copyPin,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 240),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: _pinCopied
                                          ? Colors.greenAccent.withValues(alpha: 0.15)
                                          : _rose.withValues(alpha: 0.1),
                                      border: Border.all(
                                        color: _pinCopied
                                            ? Colors.greenAccent.withValues(alpha: 0.4)
                                            : _rose.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _pinCopied
                                              ? Icons.check_rounded
                                              : Icons.copy_rounded,
                                          size: 13,
                                          color: _pinCopied
                                              ? Colors.greenAccent
                                              : _rose,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          _pinCopied ? "Copied!" : "Copy",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _pinCopied
                                                ? Colors.greenAccent
                                                : _rose,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: _rose,
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Generating…",
                                  style: TextStyle(color: _sub, fontSize: 12),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppButton(
                    text: _generatedPin.isEmpty ? "Generate" : "New PIN",
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.small,
                    isFullWidth: true,
                    onPressed: () => _generatePin(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Connect Tabs: Enter PIN | Scan QR ─────────────────────────────────────
  Widget _buildConnectTabs() {
    const tabs = [
      (Icons.dialpad_rounded, "Enter PIN"),
      (Icons.qr_code_scanner_rounded, "Scan QR"),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: List.generate(2, (i) {
          final sel = _connectTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _connectTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 230),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: sel
                      ? LinearGradient(
                          colors: [_rose, _violet],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  boxShadow: sel
                      ? [
                          BoxShadow(
                            color: _rose.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  children: [
                    Icon(tabs[i].$1, size: 18, color: sel ? Colors.white : _sub),
                    const SizedBox(height: 4),
                    Text(
                      tabs[i].$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? Colors.white : _sub,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_connectTab) {
      case 0:
        return _buildCard(
          key: const ValueKey('pin'),
          child: Column(
            children: [
              AppTextField(
                controller: _pinController,
                hintText: "8-Digit Invite PIN",
                prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                keyboardType: TextInputType.text,
                maxLength: 8,
              ),
              const SizedBox(height: 14),
              AppButton(
                text: _isConnecting ? "Connecting…" : "Connect",
                icon: const Icon(Icons.link_rounded, size: 18),
                isLoading: _isConnecting,
                isFullWidth: true,
                onPressed: _isConnecting ? null : _connectWithPin,
              ),
            ],
          ),
        );

      case 1:
        return _buildCard(
          key: const ValueKey('qr'),
          child: Column(
            children: [
              GestureDetector(
                onTap: _isConnecting ? null : _scanPartnerQR,
                child: Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [
                        _violet.withValues(alpha: 0.18),
                        _rose.withValues(alpha: 0.10),
                      ],
                    ),
                    border: Border.all(color: _rose.withValues(alpha: 0.32)),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ..._cornerBrackets(),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 48,
                            color: _rose,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Scan QR Code",
                            style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Tap to open camera or upload QR image",
                            style: TextStyle(color: _sub, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AppButton(
                text: _isConnecting ? "Connecting…" : "Scan QR Code",
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                isLoading: _isConnecting,
                isFullWidth: true,
                onPressed: _isConnecting ? null : _scanPartnerQR,
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label) => Text(
        label,
        style: TextStyle(
          color: _text,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      );

  Widget _buildCard({required Widget child, Key? key}) => AnimatedContainer(
        key: key,
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );

  List<Widget> _cornerBrackets() {
    const s = 24.0;
    const t = 3.0;
    const r = 8.0;
    final c = _rose;

    Widget b(bool top, bool left) => Positioned(
          top: top ? r : null,
          bottom: top ? null : r,
          left: left ? r : null,
          right: left ? null : r,
          child: SizedBox(
            width: s,
            height: s,
            child: CustomPaint(
              painter: _CornerPainter(top: top, left: left, color: c, thickness: t),
            ),
          ),
        );

    return [b(true, true), b(true, false), b(false, true), b(false, false)];
  }
}

// ── QR corner bracket painter ──────────────────────────────────────────────
class _CornerPainter extends CustomPainter {
  final bool top, left;
  final Color color;
  final double thickness;

  const _CornerPainter({
    required this.top,
    required this.left,
    required this.color,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    canvas.drawLine(
      Offset(left ? 0 : w, top ? 0 : h),
      Offset(left ? w : 0, top ? 0 : h),
      p,
    );
    canvas.drawLine(
      Offset(left ? 0 : w, top ? 0 : h),
      Offset(left ? 0 : w, top ? h : 0),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) =>
      old.color != color || old.thickness != thickness;
}



// ─────────────────────────────────────────────────────────────────────────────
// Romantic Connected Celebration Modal Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _ConnectedCelebrationDialog extends StatefulWidget {
  final String partnerName;
  final String userName;
  final VoidCallback onEnter;

  const _ConnectedCelebrationDialog({
    required this.partnerName,
    required this.userName,
    required this.onEnter,
  });

  @override
  State<_ConnectedCelebrationDialog> createState() =>
      _ConnectedCelebrationDialogState();
}

class _ConnectedCelebrationDialogState extends State<_ConnectedCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;
  late Animation<double> _progressAnim;

  Timer? _autoEnterTimer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.15).chain(CurveTween(curve: Curves.easeOutBack)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08).chain(CurveTween(curve: Curves.easeInOut)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 20),
    ]).animate(_animCtrl);

    _glowAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );

    _progressAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.linear),
    );

    _animCtrl.forward();

    // Auto-enter chat room after 2.4 seconds
    _autoEnterTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) {
        widget.onEnter();
      }
    });
  }

  @override
  void dispose() {
    _autoEnterTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.currentTheme.value;
    final rose = theme.primary;
    final violet = theme.secondary;
    final surface = theme.surfaceElevated;

    return PopScope(
      canPop: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 26),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: rose.withValues(alpha: 0.45),
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: rose.withValues(alpha: 0.35),
                    blurRadius: 36,
                    spreadRadius: 4,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: violet.withValues(alpha: 0.25),
                    blurRadius: 48,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Connected Celebration Icon
                  AnimatedBuilder(
                    animation: _animCtrl,
                    builder: (context, _) {
                      return Transform.scale(
                        scale: _scaleAnim.value,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer Halo
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: rose,
                              ),
                              child: const Icon(
                                Icons.link_rounded,
                                size: 42,
                                color: Colors.white,
                              ),
                            ),
                            // Connected sparkles
                            Positioned(
                              top: 2,
                              right: 4,
                              child: Icon(
                                Icons.auto_awesome,
                                size: 24,
                                color: Colors.amberAccent.withValues(alpha: _glowAnim.value),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Celebration Headline
                  Text(
                    "You're Connected!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: theme.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Connection Subtitle
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(text: "Your private space with\n"),
                        TextSpan(
                          text: widget.partnerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const TextSpan(text: " is now active! ✨"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Live Auto-Entering Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedBuilder(
                      animation: _progressAnim,
                      builder: (context, _) {
                        return LinearProgressIndicator(
                          value: _progressAnim.value,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(rose),
                          minHeight: 4,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Action Button
                  AppButton(
                    text: "Enter Shared Space",
                    icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                    isFullWidth: true,
                    onPressed: () {
                      _autoEnterTimer?.cancel();
                      HapticFeedback.mediumImpact();
                      widget.onEnter();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

