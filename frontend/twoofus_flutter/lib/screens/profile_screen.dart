import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../utils/session.dart';
import '../widgets/encryption_verification_modal.dart';
import '../widgets/passcode_lock_button.dart';
import 'partner_profile_screen.dart';
import 'passcode_setup_screen.dart';
import 'theme_selection_screen.dart';
import 'two_factor_setup_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — Professional ProfileScreen
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _birthdayCtrl = TextEditingController();

  // ── Focus Nodes ────────────────────────────────────────────────────────────
  final _usernameFocus = FocusNode();
  final _bioFocus = FocusNode();

  // ── Initial Snapshot (for change tracking) ─────────────────────────────────
  String _initialUsername = "";
  String _initialBio = "";
  String _initialBirthday = "";

  // ── State ──────────────────────────────────────────────────────────────────
  int? _userId;
  String? _userEmail;
  String? _avatarUrl;
  File? _localAvatarFile;
  bool _uploadingAvatar = false;
  bool _loading = true;
  bool _saving = false;
  int _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;

  int? _partnerId;
  String? _partnerName;
  bool _hasPasscode = false;

  // ── Palette (Reacts to Active Theme) ───────────────────────────────────────
  Color get _bg => ThemeController.currentTheme.value.bg;
  Color get _surface => ThemeController.currentTheme.value.surface;
  Color get _rose => ThemeController.currentTheme.value.primary;
  Color get _violet => ThemeController.currentTheme.value.secondary;
  Color get _lavender => ThemeController.currentTheme.value.gradientEnd;

  bool get _hasChanges =>
      _usernameCtrl.text.trim() != _initialUsername ||
      _bioCtrl.text.trim() != _initialBio ||
      _birthdayCtrl.text != _initialBirthday;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _usernameFocus.addListener(() => setState(() {}));
    _bioFocus.addListener(() => setState(() {}));

    _usernameCtrl.addListener(() => setState(() {}));
    _bioCtrl.addListener(() => setState(() {}));
    _birthdayCtrl.addListener(() => setState(() {}));

    _loadProfileData();
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

  // ── Data Loading ───────────────────────────────────────────────────────────
  Future<void> _loadProfileData() async {
    _userId = await Session.getUserId();
    _userEmail = await Session.getEmail();
    _partnerId = await Session.getCachedPartnerId();
    _partnerName = await Session.getCachedPartnerName();
    _hasPasscode = await SecurityService.hasPasscode();

    if (_userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final profile = await ApiService.getProfile(_userId!);

    if (!mounted) return;

    if (profile != null) {
      _initialUsername = profile["username"] ?? "";
      _initialBio = profile["bio"] ?? "";
      _initialBirthday = profile["birthday"] ?? "";
      _avatarUrl = profile["avatar_url"];

      _usernameCtrl.text = _initialUsername;
      _bioCtrl.text = _initialBio;
      _birthdayCtrl.text = _initialBirthday;
      if (profile["email"] != null && (profile["email"] as String).isNotEmpty) {
        _userEmail = profile["email"];
      }
    }

    setState(() => _loading = false);
  }

  // ── Avatar Handling ────────────────────────────────────────────────────────
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
            AppFeedback.showSuccess(context, "Profile picture updated successfully.", title: "Photo Updated");
          }
        } else {
          if (mounted) {
            setState(() => _uploadingAvatar = false);
            AppFeedback.showError(context, "Failed to upload avatar to server.", title: "Upload Failed");
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        AppFeedback.showError(context, "Error selecting photo: $e", title: "Photo Error");
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
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Profile Photo",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _rose.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.camera_alt_rounded, color: _rose, size: 20),
              ),
              title: const Text(
                "Take Photo",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              ),
              subtitle: const Text(
                "Use device camera",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () => _pickAndUploadAvatar(ImageSource.camera),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _violet.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.photo_library_rounded, color: _violet, size: 20),
              ),
              title: const Text(
                "Choose from Gallery",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              ),
              subtitle: const Text(
                "Select existing photo",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () => _pickAndUploadAvatar(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  // ── Save Profile ───────────────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    if (_userId == null || _saving) return;
    HapticFeedback.mediumImpact();

    final newUsername = _usernameCtrl.text.trim();
    if (newUsername.isEmpty) {
      AppFeedback.showError(context, "Username cannot be empty.", title: "Validation Error");
      return;
    }

    setState(() => _saving = true);

    final success = await ApiService.updateProfile(
      _userId!,
      newUsername,
      _bioCtrl.text.trim(),
      _birthdayCtrl.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      _initialUsername = newUsername;
      _initialBio = _bioCtrl.text.trim();
      _initialBirthday = _birthdayCtrl.text.trim();

      // Propagate locally across the app session
      final token = await Session.getToken();
      if (token != null) {
        await Session.saveLogin(
          token: token,
          userId: _userId!,
          username: newUsername,
          email: _userEmail ?? "",
        );
      }

      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showSuccess(context, "Profile changes saved successfully.", title: "Saved");
    } else {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(context, "Failed to save profile. Please try again.", title: "Save Failed");
    }
  }

  void _discardChanges() {
    HapticFeedback.lightImpact();
    setState(() {
      _usernameCtrl.text = _initialUsername;
      _bioCtrl.text = _initialBio;
      _birthdayCtrl.text = _initialBirthday;
    });
    AppFeedback.showInfo(context, "Unsaved changes discarded.");
  }

  Future<void> _pickBirthday() async {
    HapticFeedback.selectionClick();
    DateTime initial = DateTime(2000, 1, 1);
    if (_birthdayCtrl.text.isNotEmpty) {
      try {
        initial = DateTime.parse(_birthdayCtrl.text);
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1940),
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
          dialogTheme: DialogThemeData(backgroundColor: _bg),
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

  String _formatBirthdayDisplay(String raw) {
    if (raw.trim().isEmpty) return "Not specified";
    try {
      final dt = DateTime.parse(raw);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final now = DateTime.now();
      var age = now.year - dt.year;
      if (now.month < dt.month || (now.month == dt.month && now.day < dt.day)) {
        age--;
      }
      return "${months[dt.month - 1]} ${dt.day}, ${dt.year} ($age yrs)";
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
            fontSize: 44,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── Build Main ─────────────────────────────────────────────────────────────
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
              // Ambient soft gradient orbs
              Positioned(
                top: -80,
                right: -60,
                child: _Glow(color: _violet.withValues(alpha: 0.15), size: 300),
              ),
              Positioned(
                bottom: 80,
                left: -60,
                child: _Glow(color: _rose.withValues(alpha: 0.12), size: 320),
              ),

              SafeArea(
                child: Column(
                  children: [
                    // ── Professional Top Navigation Bar ──────────────────────
                    _buildTopAppBar(),

                    // ── Scrollable Body Content ──────────────────────────────
                    Expanded(
                      child: _loading
                          ? Center(child: CircularProgressIndicator(color: _rose))
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                              child: Column(
                                children: [
                                  // ── Hero Profile Card ──────────────────────
                                  _buildHeroHeader(initial),
                                  const SizedBox(height: 24),

                                  // ── Section 1: Profile Details ─────────────
                                  _buildSectionHeader(
                                    title: "PROFILE DETAILS",
                                    icon: Icons.person_outline_rounded,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildPersonalDetailsGroup(),
                                  const SizedBox(height: 24),

                                  // ── Section 2: Relationship & Security ──────
                                  _buildSectionHeader(
                                    title: "RELATIONSHIP & PRIVACY",
                                    icon: Icons.shield_outlined,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRelationshipAndSecurityGroup(),
                                  const SizedBox(height: 24),

                                  // ── Section 3: App Preferences ─────────────
                                  _buildSectionHeader(
                                    title: "PREFERENCES",
                                    icon: Icons.tune_rounded,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildPreferencesGroup(),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              // ── Floating Action Save Bar (Appears on Edit) ─────────────────
              if (_hasChanges && !_loading)
                Positioned(
                  bottom: 24,
                  left: 20,
                  right: 20,
                  child: _buildFloatingSaveDock(),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Top Navigation Bar ─────────────────────────────────────────────────────
  Widget _buildTopAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back Button
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            "My Profile",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.4,
            ),
          ),
          const Spacer(),
          // Quick Save in header if changes exist
          if (_hasChanges)
            TextButton(
              onPressed: _saving ? null : _saveProfile,
              style: TextButton.styleFrom(
                backgroundColor: _rose.withValues(alpha: 0.2),
                foregroundColor: _rose,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: _saving
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _rose),
                    )
                  : const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 6),
          const PasscodeLockButton(),
        ],
      ),
    );
  }

  // ── Hero Profile Header ────────────────────────────────────────────────────
  Widget _buildHeroHeader(String initial) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar with Edit Button
          GestureDetector(
            onTap: _showAvatarOptionsSheet,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _rose.withValues(alpha: 0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
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
                            errorBuilder: (context, error, stackTrace) => _avatarFallback(initial),
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

                // Camera Action Pill
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [_rose, _violet],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: _bg, width: 2.5),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // User Display Name
          Text(
            _usernameCtrl.text.isEmpty ? "Your Name" : _usernameCtrl.text,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),

          // Copyable Username / ID Tag
          GestureDetector(
            onTap: () {
              final idStr = _userId != null ? "#$_userId" : "@${_usernameCtrl.text}";
              Clipboard.setData(ClipboardData(text: idStr));
              HapticFeedback.lightImpact();
              AppFeedback.showSuccess(context, "Copied $idStr to clipboard", title: "Copied");
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "@${_usernameCtrl.text.isEmpty ? "username" : _usernameCtrl.text}",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_userId != null) ...[
                    Text(
                      "  •  ID #$_userId",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(width: 5),
                  Icon(
                    Icons.copy_rounded,
                    color: Colors.white.withValues(alpha: 0.4),
                    size: 11,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Relationship Connection Status Pill
          GestureDetector(
            onTap: () {
              if (_partnerId != null && _partnerName != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PartnerProfileScreen(
                      partnerId: _partnerId!,
                      partnerName: _partnerName!,
                    ),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _partnerId != null
                    ? Colors.greenAccent.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _partnerId != null
                      ? Colors.greenAccent.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _partnerId != null ? Colors.greenAccent : Colors.white38,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _partnerId != null
                        ? "Coupled with $_partnerName  •  E2EE Active"
                        : "Solo Channel  •  Pair with Partner",
                    style: TextStyle(
                      color: _partnerId != null ? Colors.greenAccent : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_partnerId != null) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.greenAccent,
                      size: 14,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 1: Personal Details Group ──────────────────────────────────────
  Widget _buildPersonalDetailsGroup() {
    final isUsernameFocused = _usernameFocus.hasFocus;
    final isBioFocused = _bioFocus.hasFocus;

    return Container(
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Display Name
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isUsernameFocused ? _rose.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.badge_outlined,
                    color: isUsernameFocused ? _rose : Colors.white60,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Display Name",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextField(
                        controller: _usernameCtrl,
                        focusNode: _usernameFocus,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                        cursorColor: _rose,
                        decoration: InputDecoration(
                          hintText: "Enter your display name",
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 15),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _divider(),

          // About You (Bio)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: isBioFocused ? _violet.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: isBioFocused ? _violet : Colors.white60,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "About You",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            "${_bioCtrl.text.length}/160",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _bioCtrl,
                        focusNode: _bioFocus,
                        maxLength: 160,
                        maxLines: 3,
                        minLines: 1,
                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                        cursorColor: _violet,
                        decoration: InputDecoration(
                          hintText: "Write a short bio, quote, or note for your partner…",
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
                          isDense: true,
                          counterText: "",
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _divider(),

          // Birthday Tile
          InkWell(
            onTap: _pickBirthday,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.cake_outlined, color: Colors.amber, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Birthday",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatBirthdayDisplay(_birthdayCtrl.text),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.edit_calendar_rounded,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          _divider(),

          // Account Email Tile (Read Only)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.alternate_email_rounded, color: Colors.blueAccent, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Registered Email",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _userEmail ?? "Not available",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "Verified",
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 2: Relationship & Security Group ───────────────────────────────
  Widget _buildRelationshipAndSecurityGroup() {
    return Container(
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Partner Profile Tile
          if (_partnerId != null && _partnerName != null) ...[
            _buildNavigationTile(
              icon: Icons.favorite_rounded,
              iconColor: _rose,
              title: "$_partnerName's Profile",
              subtitle: "View partner details, shared media & memories",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PartnerProfileScreen(
                      partnerId: _partnerId!,
                      partnerName: _partnerName!,
                    ),
                  ),
                );
              },
            ),
            _divider(),
          ],

          // End-to-End Encryption
          _buildNavigationTile(
            icon: Icons.lock_rounded,
            iconColor: Colors.greenAccent,
            title: "End-to-End Encryption (E2EE)",
            subtitle: "DTLS-SRTP & Double Ratchet safety code",
            onTap: () {
              if (_partnerId != null && _partnerName != null) {
                EncryptionVerificationModal.show(
                  context,
                  partnerId: _partnerId!,
                  partnerName: _partnerName!,
                );
              } else {
                AppFeedback.showInfo(context, "Pair with a partner first to view your E2EE safety code.");
              }
            },
          ),
          _divider(),

          // Two-Factor Authentication (2FA)
          _buildNavigationTile(
            icon: Icons.security_rounded,
            iconColor: const Color(0xFF00E5FF),
            title: "Two-Factor Authentication",
            subtitle: "Authenticator app (TOTP) & backup security codes",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TwoFactorSetupScreen()),
              );
            },
          ),
          _divider(),

          // Passcode & Biometrics
          _buildNavigationTile(
            icon: Icons.fingerprint_rounded,
            iconColor: _violet,
            title: "App Lock & Biometrics",
            subtitle: _hasPasscode ? "Passcode lock is active" : "Protect app with PIN or fingerprint",
            trailingText: _hasPasscode ? "Active" : "Set up",
            trailingTextColor: _hasPasscode ? Colors.greenAccent : _rose,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PasscodeSetupScreen(
                    mode: _hasPasscode ? PasscodeMode.change : PasscodeMode.setup,
                  ),
                ),
              );
              final updated = await SecurityService.hasPasscode();
              if (mounted) setState(() => _hasPasscode = updated);
            },
          ),
        ],
      ),
    );
  }

  // ── Section 3: Preferences Group ───────────────────────────────────────────
  Widget _buildPreferencesGroup() {
    return Container(
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Theme & Appearance
          _buildNavigationTile(
            icon: Icons.palette_outlined,
            iconColor: _lavender,
            title: "Theme & Palette",
            subtitle: "Personalize your couples space",
            trailingText: ThemeController.currentTheme.value.name,
            trailingTextColor: _rose,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ThemeSelectionScreen()),
              );
            },
          ),
          _divider(),

          // App Version & About
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.info_outline_rounded, color: Colors.white60, size: 18),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "TwoOfUs Private Space",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Version 1.0.0 (Build 43)  •  DTLS-SRTP E2EE",
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Floating Action Save Bar ───────────────────────────────────────────────
  Widget _buildFloatingSaveDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1626).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _rose.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _rose,
              boxShadow: [
                BoxShadow(
                  color: _rose.withValues(alpha: 0.8),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Unsaved profile edits",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _discardChanges,
            child: const Text(
              "Discard",
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            onPressed: _saving ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: _rose,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              elevation: 2,
            ),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    "Save",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Helper Sub-Widgets ─────────────────────────────────────────────────────
  Widget _buildSectionHeader({required String title, required IconData icon}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: _rose.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? trailingText,
    Color? trailingTextColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText,
                style: TextStyle(
                  color: trailingTextColor ?? Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.25),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.06),
        margin: const EdgeInsets.symmetric(horizontal: 16),
      );
}

// ── Soft Ambient Radial Glow Orb ─────────────────────────────────────────────
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