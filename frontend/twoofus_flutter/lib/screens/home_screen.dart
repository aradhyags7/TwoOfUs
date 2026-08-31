import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import '../widgets/passcode_lock_button.dart';
import 'login_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'partner_profile_screen.dart';
import 'theme_selection_screen.dart';
import 'security_screen.dart';
import 'media_gallery_screen.dart';

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
  String _partnerEmail = "";
  String _partnerLabel = "Not Connected";
  String _generatedPin = "";
  int _connectTab = 0; // 0 = Enter PIN  |  1 = Scan QR
  bool _pinCopied = false;
  bool _isConnecting = false;
  bool _loading = true;

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
  Color get _lavender => _theme.gradientEnd;
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadAllData();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _heartCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Data Fetching ──────────────────────────────────────────────────────────
  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadUserProfile(),
      _loadPartnerStatus(),
      _generatePin(silent: true),
    ]);
    if (mounted) {
      setState(() => _loading = false);
    }
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
        final partnerEmail = (result["partner_email"] ?? "").toString();

        setState(() {
          _isPartnerConnected = connected;
          _partnerId = partnerId;
          _partnerName = partnerName;
          _partnerEmail = partnerEmail;
          _partnerLabel = connected
              ? (partnerName.isNotEmpty ? partnerName : "Connected ❤️")
              : "Not Connected";
        });

        // If user is connected to a partner, save partner cache and directly navigate to ChatScreen
        if (connected && partnerId != null) {
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

  Future<void> _generatePin({bool silent = false}) async {
    try {
      final userId = await Session.getUserId();
      final token = await Session.getToken();
      if (userId == null) return;

      final result = await ApiService.generatePin(userId, token: token);
      if (result != null && mounted) {
        setState(() => _generatedPin = result["pin"] ?? "");
        if (!silent) _toast("New PIN generated ❤️");
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

  Future<void> _connectWithPin() async {
    final pin = _pinController.text.trim().toUpperCase();
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
      _toast("Connected successfully with your partner ❤️");
      await _loadPartnerStatus(autoNavigate: true);
    } else {
      _toast("Invalid PIN or connection failed. Please check and try again.", isError: true);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? const Color(0xFF4A0E17) : _violet,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      ),
    );
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
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (b) =>
                    LinearGradient(colors: [_rose, _violet]).createShader(b),
                blendMode: BlendMode.srcIn,
                child: const Icon(Icons.logout_rounded, size: 42, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                "Sign Out",
                style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                "Are you sure you want to sign out of TwoOfUs?",
                textAlign: TextAlign.center,
                style: TextStyle(color: _sub, fontSize: 14),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        "Stay",
                        style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [_rose, _violet]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await Session.clear();
                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          "Sign out",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
              // ── Ambient background glows ───────────────────────────────────
              Positioned(
                top: -90,
                right: -70,
                child: _Glow(color: _rose.withValues(alpha: 0.16), size: 340),
              ),
              Positioned(
                bottom: -110,
                left: -80,
                child: _Glow(color: _violet.withValues(alpha: 0.14), size: 380),
              ),

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

                              // ── 3. Connected Couple Space OR Pairing ───────
                              if (_isPartnerConnected) ...[
                                _buildConnectedCoupleHero(),
                              ] else ...[
                                _buildStatusCard(),
                                const SizedBox(height: 26),
                                _buildSectionLabel("Share with Partner"),
                                const SizedBox(height: 12),
                                _buildShareSection(),
                                const SizedBox(height: 26),
                                _buildSectionLabel("Connect with Partner"),
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
          ScaleTransition(
            scale: _heartScale,
            child: ShaderMask(
              shaderCallback: (b) =>
                  LinearGradient(colors: [_rose, _violet]).createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.favorite_rounded, size: 28, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (b) => LinearGradient(
              colors: [_rose, _lavender],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ).createShader(b),
            blendMode: BlendMode.srcIn,
            child: const Text(
              "TwoOfUs",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.6,
              ),
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
              width: 38,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _rose.withValues(alpha: 0.6), width: 1.8),
                boxShadow: [
                  BoxShadow(
                    color: _rose.withValues(alpha: 0.25),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipOval(
                child: _userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
                    ? Image.network(
                        _userAvatarUrl!.startsWith('http')
                            ? "${_userAvatarUrl!}?v=$_avatarCacheKey"
                            : "${ApiService.baseUrl}/${_userAvatarUrl!.startsWith('/') ? _userAvatarUrl!.substring(1) : _userAvatarUrl!}?v=$_avatarCacheKey",
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarInitialWidget(size: 38),
                      )
                    : _avatarInitialWidget(size: 38),
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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar with camera/edit badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_rose, _violet],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _rose.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(2.5),
                  child: ClipOval(
                    child: _userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
                        ? Image.network(
                            _userAvatarUrl!.startsWith('http')
                                ? "${_userAvatarUrl!}?v=$_avatarCacheKey"
                                : "${ApiService.baseUrl}/${_userAvatarUrl!.startsWith('/') ? _userAvatarUrl!.substring(1) : _userAvatarUrl!}?v=$_avatarCacheKey",
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _avatarInitialWidget(size: 60),
                          )
                        : _avatarInitialWidget(size: 60),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _violet,
                      shape: BoxShape.circle,
                      border: Border.all(color: _surface, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),

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
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _rose.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _rose.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          "You",
                          style: TextStyle(
                            color: _rose,
                            fontSize: 10.5,
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
                        : (_userEmail.isNotEmpty ? _userEmail : "Tap to complete your profile bio ❤️"),
                    style: TextStyle(
                      color: _sub,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Arrow action
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _rose.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: _rose,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarInitialWidget({required double size}) {
    final initial = _username.isNotEmpty ? _username.substring(0, 1).toUpperCase() : "U";
    return Container(
      width: size,
      height: size,
      color: _surface,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: _rose,
            fontSize: size * 0.44,
            fontWeight: FontWeight.w800,
          ),
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
            separatorBuilder: (_, __) => const SizedBox(width: 10),
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

  // ── 3. Connected Couple Space ──────────────────────────────────────────────
  Widget _buildConnectedCoupleHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("Connected Couple Space ❤️"),
        const SizedBox(height: 12),

        // Couple Visual Card
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
              // Two Avatars + Heart Line
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // User Avatar
                  Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _rose, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: _rose.withValues(alpha: 0.3),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
                              ? Image.network(
                                  _userAvatarUrl!.startsWith('http')
                                      ? "${_userAvatarUrl!}?v=$_avatarCacheKey"
                                      : "${ApiService.baseUrl}/${_userAvatarUrl!.startsWith('/') ? _userAvatarUrl!.substring(1) : _userAvatarUrl!}?v=$_avatarCacheKey",
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _avatarInitialWidget(size: 64),
                                )
                              : _avatarInitialWidget(size: 64),
                        ),
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

                  // Beating Love Connection Line
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
                              Icons.favorite_rounded,
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
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [_violet, _lavender],
                                ),
                                border: Border.all(color: _violet, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: _violet.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.favorite,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: AnimatedBuilder(
                                animation: _pulseAnim,
                                builder: (_, __) => Transform.scale(
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
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_rose, _violet],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _rose.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _openChatScreen,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.chat_bubble_rounded, size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "Open Private Chat",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                icon: Icons.favorite_outline_rounded,
                label: "Partner Profile",
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
                "Partner Status",
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
              "Pair Now",
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: _border),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _sub.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Pairing QR Code",
              style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "Have your partner scan this code to connect instantly",
              textAlign: TextAlign.center,
              style: TextStyle(color: _sub, fontSize: 13),
            ),
            const SizedBox(height: 22),
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
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _generatedPin));
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  _toast("Pairing PIN copied to clipboard! ❤️");
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text("Copy PIN to Share"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _rose,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
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
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: _rose.withValues(alpha: 0.08),
                        border: Border.all(color: _rose.withValues(alpha: 0.30)),
                      ),
                      child: TextButton(
                        onPressed: _showPairingQRModal,
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fullscreen_rounded, size: 15, color: _rose),
                            const SizedBox(width: 6),
                            Text(
                              "View QR",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _rose,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                                ShaderMask(
                                  shaderCallback: (b) =>
                                      LinearGradient(colors: [_rose, _violet])
                                          .createShader(b),
                                  blendMode: BlendMode.srcIn,
                                  child: Text(
                                    _generatedPin.length == 8
                                        ? '${_generatedPin.substring(0, 4)}-${_generatedPin.substring(4, 8)}'
                                        : _generatedPin,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 2,
                                      color: Colors.white,
                                    ),
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
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_rose, _violet],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _rose.withValues(alpha: 0.30),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () => _generatePin(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.refresh_rounded, size: 15, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              _generatedPin.isEmpty ? "Generate" : "New PIN",
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
              _buildField(
                controller: _pinController,
                hint: "Partner 8-Digit Invite PIN",
                icon: Icons.vpn_key_rounded,
                type: TextInputType.text,
                maxLength: 8,
              ),
              const SizedBox(height: 14),
              _buildGradientBtn(
                label: _isConnecting ? "Connecting…" : "Connect",
                icon: Icons.link_rounded,
                isLoading: _isConnecting,
                onTap: _isConnecting ? () {} : _connectWithPin,
              ),
            ],
          ),
        );

      case 1:
        return _buildCard(
          key: const ValueKey('qr'),
          child: Column(
            children: [
              Container(
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
                        ShaderMask(
                          shaderCallback: (b) =>
                              LinearGradient(colors: [_rose, _violet]).createShader(b),
                          blendMode: BlendMode.srcIn,
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Scan Partner's QR Code",
                          style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildGradientBtn(
                label: "Scan Partner QR",
                icon: Icons.camera_alt_rounded,
                onTap: () => _toast("Please use PIN connection for instant pairing ❤️"),
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

  Widget _buildGradientBtn({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isLoading = false,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_rose, _violet],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _rose.withValues(alpha: 0.32),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? type,
    int? maxLength,
  }) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: TextField(
          controller: controller,
          keyboardType: type,
          textCapitalization: TextCapitalization.characters,
          maxLength: maxLength,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          style: TextStyle(
            color: _text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
          cursorColor: _rose,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: _sub,
              fontSize: 14,
              letterSpacing: 0,
              fontWeight: FontWeight.normal,
            ),
            prefixIcon: Icon(icon, size: 20, color: _rose.withValues(alpha: 0.8)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          ),
        ),
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

  List<Widget> _smallCornerBrackets() {
    const s = 18.0;
    const t = 2.5;
    const r = 6.0;
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

// ── Radial glow blob ───────────────────────────────────────────────────────
class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
            stops: const [0.0, 1.0],
          ),
        ),
      );
}
