import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../utils/session.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — Focused & Professional Profile Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _birthdayCtrl = TextEditingController();

  // ── Focus Nodes ────────────────────────────────────────────────────────────
  final _nameFocus = FocusNode();
  final _bioFocus = FocusNode();

  // ── Initial Snapshot (Tracks edits) ────────────────────────────────────────
  String _initialName = "";
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

  // ── Theme Palette ──────────────────────────────────────────────────────────
  Color get _bg => ThemeController.currentTheme.value.bg;
  Color get _surface => ThemeController.currentTheme.value.surface;
  Color get _rose => ThemeController.currentTheme.value.primary;
  Color get _violet => ThemeController.currentTheme.value.secondary;

  bool get _hasChanges =>
      _nameCtrl.text.trim() != _initialName ||
      _bioCtrl.text.trim() != _initialBio ||
      _birthdayCtrl.text != _initialBirthday;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _nameFocus.addListener(() => setState(() {}));
    _bioFocus.addListener(() => setState(() {}));

    _nameCtrl.addListener(() => setState(() {}));
    _bioCtrl.addListener(() => setState(() {}));
    _birthdayCtrl.addListener(() => setState(() {}));

    _loadProfileData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _birthdayCtrl.dispose();
    _nameFocus.dispose();
    _bioFocus.dispose();
    super.dispose();
  }

  // ── Data Loading ───────────────────────────────────────────────────────────
  Future<void> _loadProfileData() async {
    _userId = await Session.getUserId();
    _userEmail = await Session.getEmail();

    if (_userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final profile = await ApiService.getProfile(_userId!);

    if (!mounted) return;

    if (profile != null) {
      _initialName = profile["username"] ?? "";
      _initialBio = profile["bio"] ?? "";
      _initialBirthday = profile["birthday"] ?? "";
      _avatarUrl = profile["avatar_url"];

      _nameCtrl.text = _initialName;
      _bioCtrl.text = _initialBio;
      _birthdayCtrl.text = _initialBirthday;
      if (profile["email"] != null && (profile["email"] as String).isNotEmpty) {
        _userEmail = profile["email"];
      }
    }

    setState(() => _loading = false);
  }

  // ── Avatar Pick & Upload ───────────────────────────────────────────────────
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
            AppFeedback.showSuccess(context, "Profile picture updated.", title: "Photo Updated");
          }
        } else {
          if (mounted) {
            setState(() => _uploadingAvatar = false);
            AppFeedback.showError(context, "Failed to upload photo to server.", title: "Upload Failed");
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
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
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
              "Change Profile Photo",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
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
                "Select existing picture",
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

    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) {
      AppFeedback.showError(context, "Name cannot be empty.", title: "Validation Error");
      return;
    }

    setState(() => _saving = true);

    final success = await ApiService.updateProfile(
      _userId!,
      newName,
      _bioCtrl.text.trim(),
      _birthdayCtrl.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      _initialName = newName;
      _initialBio = _bioCtrl.text.trim();
      _initialBirthday = _birthdayCtrl.text.trim();

      // Synchronize locally with app session
      final token = await Session.getToken();
      if (token != null) {
        await Session.saveLogin(
          token: token,
          userId: _userId!,
          username: newName,
          email: _userEmail ?? "",
        );
      }

      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showSuccess(context, "Profile updated successfully.", title: "Saved");
    } else {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(context, "Failed to save profile. Please try again.", title: "Save Failed");
    }
  }

  void _discardChanges() {
    HapticFeedback.lightImpact();
    setState(() {
      _nameCtrl.text = _initialName;
      _bioCtrl.text = _initialBio;
      _birthdayCtrl.text = _initialBirthday;
    });
    AppFeedback.showInfo(context, "Edits discarded.");
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
    if (raw.trim().isEmpty) return "Not set";
    try {
      final dt = DateTime.parse(raw);
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
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
    final initial = _nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : "?";

    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: activeTheme.bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              "My Profile",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            centerTitle: true,
            actions: [
              TextButton(
                onPressed: (_hasChanges && !_saving) ? _saveProfile : null,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: _rose, strokeWidth: 2),
                      )
                    : Text(
                        "Save",
                        style: TextStyle(
                          color: _hasChanges ? _rose : Colors.white24,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: _loading
              ? Center(child: CircularProgressIndicator(color: _rose))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Profile Photo Section ─────────────────────────────
                      const SizedBox(height: 12),
                      _buildAvatarHero(initial),
                      const SizedBox(height: 28),

                      // ── Card 1: Identity & Name ────────────────────────────
                      _buildCardGroup(
                        title: "PROFILE INFO",
                        children: [
                          _buildTextInputRow(
                            label: "Display Name",
                            controller: _nameCtrl,
                            focusNode: _nameFocus,
                            icon: Icons.person_rounded,
                            hint: "Enter your display name",
                            helperText: "Visible to your partner in chats and calls",
                          ),
                          _divider(),
                          _buildTextInputRow(
                            label: "About (Bio)",
                            controller: _bioCtrl,
                            focusNode: _bioFocus,
                            icon: Icons.edit_note_rounded,
                            hint: "Write a short note for your partner…",
                            helperText: "Your personal status or message",
                            maxLines: 3,
                            maxLength: 160,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Card 2: Personal Details ───────────────────────────
                      _buildCardGroup(
                        title: "PERSONAL DETAILS",
                        children: [
                          _buildTappableRow(
                            label: "Birthday",
                            icon: Icons.cake_rounded,
                            value: _formatBirthdayDisplay(_birthdayCtrl.text),
                            onTap: _pickBirthday,
                            trailing: Icon(
                              Icons.calendar_today_rounded,
                              color: Colors.white.withValues(alpha: 0.35),
                              size: 16,
                            ),
                          ),
                          _divider(),
                          _buildInfoRow(
                            label: "Email",
                            icon: Icons.alternate_email_rounded,
                            value: _userEmail ?? "Not set",
                            badge: "Verified",
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // ── Bottom Save Changes Button (if edited) ────────────
                      if (_hasChanges)
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _saving ? null : _saveProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _rose,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 3,
                                ),
                                child: _saving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                      )
                                    : const Text(
                                        "Save Changes",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _discardChanges,
                              child: Text(
                                "Discard changes",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  // ── Avatar Hero ────────────────────────────────────────────────────────────
  Widget _buildAvatarHero(String initial) {
    return Column(
      children: [
        GestureDetector(
          onTap: _showAvatarOptionsSheet,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _rose.withValues(alpha: 0.5),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _rose.withValues(alpha: 0.25),
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

              // Camera Badge
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _rose,
                    shape: BoxShape.circle,
                    border: Border.all(color: _bg, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _showAvatarOptionsSheet,
          child: Text(
            "Change Photo",
            style: TextStyle(
              color: _rose,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ── Card Group Container ───────────────────────────────────────────────────
  Widget _buildCardGroup({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  // ── Input Row ──────────────────────────────────────────────────────────────
  Widget _buildTextInputRow({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required IconData icon,
    required String hint,
    String? helperText,
    int maxLines = 1,
    int? maxLength,
  }) {
    final isFocused = focusNode.hasFocus;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            margin: maxLines > 1 ? const EdgeInsets.only(top: 2) : null,
            decoration: BoxDecoration(
              color: isFocused ? _rose.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: isFocused ? _rose : Colors.white60, size: 18),
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
                      label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (maxLength != null)
                      Text(
                        "${controller.text.length}/$maxLength",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: maxLines,
                  maxLength: maxLength,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                  cursorColor: _rose,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 15),
                    isDense: true,
                    counterText: "",
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    border: InputBorder.none,
                  ),
                ),
                if (helperText != null && !isFocused && controller.text.isEmpty)
                  Text(
                    helperText,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tappable Row (Birthday) ────────────────────────────────────────────────
  Widget _buildTappableRow({
    required String label,
    required IconData icon,
    required String value,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white60, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  // ── Info Row (Email) ───────────────────────────────────────────────────────
  Widget _buildInfoRow({
    required String label,
    required IconData icon,
    required String value,
    String? badge,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white60, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.06),
        margin: const EdgeInsets.symmetric(horizontal: 16),
      );
}