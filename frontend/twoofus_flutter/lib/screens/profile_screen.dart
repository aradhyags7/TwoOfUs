import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import '../widgets/passcode_lock_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — ProfileScreen
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _usernameCtrl  = TextEditingController();
  final _bioCtrl       = TextEditingController();
  final _birthdayCtrl  = TextEditingController();

  // ── Focus nodes ────────────────────────────────────────────────────────────
  final _usernameFocus = FocusNode();
  final _bioFocus      = FocusNode();

  // ── State ──────────────────────────────────────────────────────────────────
  int?    _userId;
  String? _avatarUrl;
  File?   _localAvatarFile;
  bool    _uploadingAvatar = false;
  bool    _loading = true;
  bool    _saving  = false;
  int     _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;

  // ── Palette ────────────────────────────────────────────────────────────────
  Color get _bg       => ThemeController.currentTheme.value.bg;
  Color get _surface  => ThemeController.currentTheme.value.surface;
  Color get _rose     => ThemeController.currentTheme.value.primary;
  Color get _violet   => ThemeController.currentTheme.value.secondary;
  Color get _lavender => ThemeController.currentTheme.value.gradientEnd;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _usernameFocus.addListener(() => setState(() {}));
    _bioFocus.addListener(() => setState(() {}));

    _usernameCtrl.addListener(() => setState(() {}));
    _bioCtrl.addListener(() => setState(() {}));

    _loadProfile();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _birthdayCtrl.dispose();
    _usernameFocus.dispose();
    _bioFocus.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────
  Future<void> _loadProfile() async {
    _userId = await Session.getUserId();

    if (_userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final profile = await ApiService.getProfile(_userId!);

    if (!mounted) return;

    if (profile != null) {
      _usernameCtrl.text = profile["username"] ?? "";
      _bioCtrl.text      = profile["bio"]      ?? "";
      _birthdayCtrl.text = profile["birthday"] ?? "";
      _avatarUrl         = profile["avatar_url"];
    }

    setState(() => _loading = false);
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    HapticFeedback.lightImpact();
    Navigator.pop(context);

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked == null) return;

      final file = File(picked.path);
      setState(() {
        _localAvatarFile = file;
        _uploadingAvatar = true;
      });

      if (_userId != null) {
        final uploadedPath = await ApiService.uploadAvatar(_userId!, file);
        if (uploadedPath != null) {
          if (mounted) {
            setState(() {
              _avatarUrl = uploadedPath;
              _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;
              _uploadingAvatar = false;
            });
            _showSnack("Profile picture updated ❤️");
          }
        } else {
          if (mounted) {
            setState(() => _uploadingAvatar = false);
            _showSnack("Failed to save picture to server", isError: true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        _showSnack("Error selecting photo: $e", isError: true);
      }
    }
  }

  void _showAvatarOptionsSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            ShaderMask(
              shaderCallback: (b) => LinearGradient(
                colors: [_rose, _lavender],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Text(
                "Change Profile Photo",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Take Photo Tile
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _rose.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.camera_alt_rounded, color: _rose, size: 22),
              ),
              title: const Text(
                "Take Photo",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                "Use camera to capture new picture",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () => _pickAndUploadAvatar(ImageSource.camera),
            ),
            const SizedBox(height: 8),

            // Choose from Gallery Tile
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _violet.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.photo_library_rounded, color: _violet, size: 22),
              ),
              title: const Text(
                "Choose from Gallery",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                "Select existing photo from device",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () => _pickAndUploadAvatar(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? const Color(0xFF3D0017) : _violet,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (_userId == null) return;
    HapticFeedback.lightImpact();

    setState(() => _saving = true);

    final success = await ApiService.updateProfile(
      _userId!,
      _usernameCtrl.text.trim(),
      _bioCtrl.text.trim(),
      _birthdayCtrl.text.trim(),
    );

    if (!mounted) return;

    setState(() => _saving = false);
    _showSnack(success ? "Profile updated ❤️" : "Update failed — try again", isError: !success);
  }

  Future<void> _pickBirthday() async {
    HapticFeedback.selectionClick();
    DateTime initial = DateTime(2000);
    if (_birthdayCtrl.text.isNotEmpty) {
      try {
        initial = DateTime.parse(_birthdayCtrl.text);
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(
            primary: _rose,
            onPrimary: Colors.white,
            surface: _surface,
            onSurface: Colors.white,
            secondary: _violet,
          ),
          dialogBackgroundColor: _bg,
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: _rose),
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        _birthdayCtrl.text = picked.toIso8601String().split("T")[0];
      });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _formatBirthday(String raw) {
    if (raw.isEmpty) return "Not set";
    try {
      final dt = DateTime.parse(raw);
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return raw;
    }
  }

  Widget _avatarFallback(String initial) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [_rose, _violet],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required FocusNode? focusNode,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    final focused = focusNode?.hasFocus ?? false;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _surface,
        border: Border.all(
          color: focused ? _rose.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.07),
          width: focused ? 1.5 : 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: _rose.withValues(alpha: 0.12),
                  blurRadius: 14,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: maxLines,
        readOnly: readOnly,
        onTap: onTap,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        cursorColor: _rose,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.28),
            fontSize: 15,
          ),
          prefixIcon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Icon(
              icon,
              key: ValueKey(focused),
              color: focused ? _rose : Colors.white.withValues(alpha: 0.28),
              size: 20,
            ),
          ),
          suffixIcon: readOnly
              ? Icon(Icons.edit_calendar_rounded,
                  color: Colors.white.withValues(alpha: 0.28), size: 18)
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            vertical: maxLines > 1 ? 14 : 18,
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child, EdgeInsets? padding}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: child,
    );
  }

  Widget _stat(String emoji, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 40,
        color: Colors.white.withValues(alpha: 0.08),
      );

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final initial = _usernameCtrl.text.isNotEmpty
        ? _usernameCtrl.text[0].toUpperCase()
        : "?";

    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: activeTheme.bg,
          body: Stack(
            children: [
              // ── Ambient corner glows ─────────────────────────────────────────
              Positioned(
                top: -80, right: -60,
                child: _Glow(color: _violet.withValues(alpha: 0.12), size: 320),
              ),
              Positioned(
                bottom: -100, left: -80,
                child: _Glow(color: _rose.withValues(alpha: 0.10), size: 360),
              ),

              SafeArea(
                child: Column(
                  children: [
                    // ── App bar ─────────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 20, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 2),
                          ShaderMask(
                            shaderCallback: (b) => LinearGradient(
                              colors: [_rose, _lavender],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ).createShader(b),
                            blendMode: BlendMode.srcIn,
                            child: const Text(
                              "My Profile",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const PasscodeLockButton(),
                        ],
                      ),
                    ),

                    // ── Body ────────────────────────────────────────────────────
                    Expanded(
                      child: _loading
                          ? Center(child: CircularProgressIndicator(color: _rose))
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                              child: Column(
                                children: [
                                  // ── Avatar with Interactive Picture Button ──
                                  GestureDetector(
                                    onTap: _showAvatarOptionsSheet,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.bottomRight,
                                      children: [
                                        Container(
                                          width: 120,
                                          height: 120,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: _rose.withValues(alpha: 0.35),
                                                blurRadius: 28,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: ClipOval(
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                if (_localAvatarFile != null)
                                                  Image.file(
                                                    _localAvatarFile!,
                                                    fit: BoxFit.cover,
                                                  )
                                                else if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                                                  Image.network(
                                                    _avatarUrl!.startsWith('http')
                                                        ? "${_avatarUrl!}?v=$_avatarCacheKey"
                                                        : "${ApiService.baseUrl}/${_avatarUrl!.startsWith('/') ? _avatarUrl!.substring(1) : _avatarUrl!}?v=$_avatarCacheKey",
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => _avatarFallback(initial),
                                                  )
                                                else
                                                  _avatarFallback(initial),

                                                if (_uploadingAvatar)
                                                  Container(
                                                    color: Colors.black54,
                                                    child: const Center(
                                                      child: CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 2.5,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Camera Badge Picture Button
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: [_rose, _violet],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              border: Border.all(
                                                color: _bg,
                                                width: 3.0,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: _rose.withValues(alpha: 0.4),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 18),

                                  // Live display name
                                  ShaderMask(
                                    shaderCallback: (b) => LinearGradient(
                                      colors: [_rose, _lavender],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ).createShader(b),
                                    blendMode: BlendMode.srcIn,
                                    child: Text(
                                      _usernameCtrl.text.isEmpty
                                          ? "Your Name"
                                          : _usernameCtrl.text,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 4),

                                  Text(
                                    "@${_usernameCtrl.text.isEmpty ? "username" : _usernameCtrl.text}",
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.38),
                                      fontSize: 14,
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  // ── About Me card ────────────────────────────
                                  _buildCard(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            ShaderMask(
                                              shaderCallback: (b) => LinearGradient(
                                                colors: [_rose, _violet],
                                              ).createShader(b),
                                              blendMode: BlendMode.srcIn,
                                              child: const Icon(
                                                Icons.favorite_rounded,
                                                size: 15,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              "About Me",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          _bioCtrl.text.isEmpty
                                              ? "Tell your partner about yourself…"
                                              : _bioCtrl.text,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: _bioCtrl.text.isEmpty ? 0.28 : 0.65,
                                            ),
                                            fontSize: 14,
                                            height: 1.55,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  // ── Stats row ────────────────────────────────
                                  _buildCard(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 16),
                                    child: Row(
                                      children: [
                                        _stat("❤️", "Connected"),
                                        _statDivider(),
                                        _stat(
                                          "🎂",
                                          _birthdayCtrl.text.isEmpty
                                              ? "Birthday"
                                              : _formatBirthday(_birthdayCtrl.text),
                                        ),
                                        _statDivider(),
                                        _stat("📅", "Memories"),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 28),

                                  // ── Edit fields ──────────────────────────────
                                  // Username
                                  _buildField(
                                    controller: _usernameCtrl,
                                    focusNode: _usernameFocus,
                                    hint: "Username",
                                    icon: Icons.person_outline_rounded,
                                  ),

                                  const SizedBox(height: 14),

                                  // Bio (multiline)
                                  _buildField(
                                    controller: _bioCtrl,
                                    focusNode: _bioFocus,
                                    hint: "Tell your partner about yourself…",
                                    icon: Icons.edit_outlined,
                                    maxLines: 4,
                                  ),

                                  const SizedBox(height: 14),

                                  // Birthday — read-only, opens date picker
                                  _buildField(
                                    controller: _birthdayCtrl,
                                    focusNode: null,
                                    hint: "Birthday",
                                    icon: Icons.cake_outlined,
                                    readOnly: true,
                                    onTap: _pickBirthday,
                                  ),

                                  const SizedBox(height: 32),

                                  // ── Save button ──────────────────────────────
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: _saving
                                            ? null
                                            : LinearGradient(
                                                colors: [_rose, _violet],
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ),
                                        color: _saving ? _surface : null,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: _saving
                                            ? []
                                            : [
                                                BoxShadow(
                                                  color: _rose.withValues(alpha: 0.38),
                                                  blurRadius: 22,
                                                  offset: const Offset(0, 7),
                                                ),
                                              ],
                                      ),
                                      child: ElevatedButton(
                                        onPressed: _saving ? null : _saveProfile,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          disabledBackgroundColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: _saving
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Text(
                                                "Save Changes",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 17,
                                                  letterSpacing: 0.3,
                                                ),
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
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Radial glow blob ──────────────────────────────────────────────────────────
class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
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
}