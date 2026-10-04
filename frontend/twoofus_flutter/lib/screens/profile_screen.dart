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
// TwoOfUs — Telegram & Apple ID Styled Professional Profile Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  int? _userId;
  String _name = "";
  String _bio = "";
  String _birthday = "";
  String? _userEmail;
  String? _avatarUrl;
  File? _localAvatarFile;

  String? _partnerName;

  bool _loading = true;
  bool _uploadingAvatar = false;
  int _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;

  final ScrollController _scrollController = ScrollController();
  bool _showCollapsedTitle = false;

  // ── Palette ────────────────────────────────────────────────────────────────
  Color get _bg => ThemeController.currentTheme.value.bg;
  Color get _surface => ThemeController.currentTheme.value.surface;
  Color get _rose => ThemeController.currentTheme.value.primary;
  Color get _violet => ThemeController.currentTheme.value.secondary;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadProfileData();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollController.hasClients && _scrollController.offset > 120;
    if (show != _showCollapsedTitle) {
      setState(() => _showCollapsedTitle = show);
    }
  }

  // ── Data Loading ───────────────────────────────────────────────────────────
  Future<void> _loadProfileData() async {
    _userId = await Session.getUserId();
    _userEmail = await Session.getEmail();
    _partnerName = await Session.getCachedPartnerName();

    if (_userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final profile = await ApiService.getProfile(_userId!);

    if (!mounted) return;

    if (profile != null) {
      _name = profile["username"] ?? "";
      _bio = profile["bio"] ?? "";
      _birthday = profile["birthday"] ?? "";
      _avatarUrl = profile["avatar_url"];
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
              "Profile Photo",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (_avatarUrl != null || _localAvatarFile != null) ...[
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
                ),
                title: const Text(
                  "View Full Photo",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAvatarLightbox();
                },
              ),
              const SizedBox(height: 4),
            ],
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
            const SizedBox(height: 4),
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

  void _openAvatarLightbox() {
    final imageProvider = _localAvatarFile != null
        ? FileImage(_localAvatarFile!) as ImageProvider
        : (_avatarUrl != null && _avatarUrl!.isNotEmpty
            ? NetworkImage(_avatarUrl!.startsWith('http')
                ? "${_avatarUrl!}?v=$_avatarCacheKey"
                : "${ApiService.baseUrl}/${_avatarUrl!.startsWith('/') ? _avatarUrl!.substring(1) : _avatarUrl!}?v=$_avatarCacheKey")
            : null);

    if (imageProvider == null) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: InteractiveViewer(
                child: Image(
                  image: imageProvider,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showAvatarOptionsSheet();
              },
              icon: const Icon(Icons.camera_alt_rounded, color: Colors.white70),
              label: const Text("Change Photo", style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit Name Sheet ────────────────────────────────────────────────────────
  void _showEditNameSheet() {
    final ctrl = TextEditingController(text: _name);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Edit Display Name",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  "This is how your partner will see you in chats and calls.",
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _rose.withValues(alpha: 0.4)),
                  ),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    cursorColor: _rose,
                    decoration: InputDecoration(
                      hintText: "Enter your name",
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                        onPressed: () => ctrl.clear(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final newName = ctrl.text.trim();
                            if (newName.isEmpty) {
                              AppFeedback.showError(ctx, "Name cannot be empty.");
                              return;
                            }
                            setSheetState(() => isSaving = true);
                            final ok = await ApiService.updateProfile(_userId!, newName, _bio, _birthday);
                            if (!ctx.mounted) return;
                            if (ok) {
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
                              setState(() => _name = newName);
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              AppFeedback.showSuccess(context, "Display name updated.");
                            } else {
                              setSheetState(() => isSaving = false);
                              if (ctx.mounted) AppFeedback.showError(ctx, "Failed to update name.");
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _rose,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Save Changes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Edit Bio Sheet ─────────────────────────────────────────────────────────
  void _showEditBioSheet() {
    final ctrl = TextEditingController(text: _bio);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Edit Bio / Status",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  "A note, inside joke, or feeling visible to your partner.",
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _violet.withValues(alpha: 0.4)),
                  ),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 4,
                    maxLength: 160,
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                    cursorColor: _violet,
                    decoration: const InputDecoration(
                      hintText: "What's on your mind…",
                      hintStyle: TextStyle(color: Colors.white24),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Quick suggestions
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _bioChip("Forever & always 💖", ctrl),
                    _bioChip("Thinking of you 🥰", ctrl),
                    _bioChip("Best partner ever 🌟", ctrl),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final newBio = ctrl.text.trim();
                            setSheetState(() => isSaving = true);
                            final ok = await ApiService.updateProfile(_userId!, _name, newBio, _birthday);
                            if (!ctx.mounted) return;
                            if (ok) {
                              if (mounted) {
                                setState(() => _bio = newBio);
                                Navigator.pop(sheetCtx);
                                AppFeedback.showSuccess(context, "Bio updated.");
                              }
                            } else {
                              setSheetState(() => isSaving = false);
                              AppFeedback.showError(ctx, "Failed to update bio.");
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _violet,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Save Bio", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bioChip(String text, TextEditingController ctrl) {
    return InkWell(
      onTap: () {
        ctrl.text = text;
        ctrl.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }

  // ── Pick Birthday ──────────────────────────────────────────────────────────
  Future<void> _pickBirthday() async {
    HapticFeedback.selectionClick();
    DateTime initial = DateTime(2000, 1, 1);
    if (_birthday.isNotEmpty) {
      try {
        initial = DateTime.parse(_birthday);
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
      final newBirthday = picked.toIso8601String().split("T")[0];
      final ok = await ApiService.updateProfile(_userId!, _name, _bio, newBirthday);
      if (ok && mounted) {
        setState(() => _birthday = newBirthday);
        AppFeedback.showSuccess(context, "Birthday updated.");
      }
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
            fontSize: 42,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── Build Main Screen ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final initial = _name.isNotEmpty ? _name[0].toUpperCase() : "?";

    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: activeTheme.bg,
          appBar: AppBar(
            backgroundColor: _showCollapsedTitle ? _surface.withValues(alpha: 0.95) : Colors.transparent,
            elevation: _showCollapsedTitle ? 2 : 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
            title: AnimatedOpacity(
              opacity: _showCollapsedTitle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                _name.isNotEmpty ? _name : "Profile",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                      tooltip: "Edit Name",
                      onPressed: _showEditNameSheet,
                    ),
                  ),
                ),
              ),
            ],
          ),
          extendBodyBehindAppBar: true,
          body: _loading
              ? Center(child: CircularProgressIndicator(color: _rose))
              : SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      // ── Hero Header ─────────────────────────────────────────
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Ambient decorative background mesh glow
                          Container(
                            height: 290,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _rose.withValues(alpha: 0.28),
                                  _violet.withValues(alpha: 0.18),
                                  _bg,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),

                          // Header Content
                          Positioned(
                            top: 100,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Avatar with camera badge
                                GestureDetector(
                                  onTap: _showAvatarOptionsSheet,
                                  child: Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      Container(
                                        width: 104,
                                        height: 104,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 3.5),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _rose.withValues(alpha: 0.35),
                                              blurRadius: 24,
                                              spreadRadius: 2,
                                            ),
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.4),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: ClipOval(
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              if (_localAvatarFile != null)
                                                Image.file(_localAvatarFile!, fit: BoxFit.cover)
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
                                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // Camera Edit Badge
                                      Positioned(
                                        bottom: 2,
                                        right: 2,
                                        child: Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [_rose, _violet],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.35),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.camera_alt_rounded,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Name
                                Text(
                                  _name.isNotEmpty ? _name : "Your Name",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    shadows: [
                                      Shadow(color: Colors.black45, blurRadius: 10),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // Handle Chip with Tap-to-Copy
                                GestureDetector(
                                  onTap: () {
                                    final text = "@${_name.isNotEmpty ? _name : 'username'}";
                                    Clipboard.setData(ClipboardData(text: text));
                                    HapticFeedback.lightImpact();
                                    AppFeedback.showSuccess(context, "Copied $text to clipboard");
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "@${_name.isNotEmpty ? _name : "username"}",
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.8),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.copy_rounded,
                                          color: Colors.white.withValues(alpha: 0.5),
                                          size: 12,
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

                      // ── Inset Grouped Profile Information ─────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Group 1: Identity & Bio ─────────────────────
                            _buildGroupCard(
                              title: "PROFILE INFO",
                              children: [
                                _buildProfileTile(
                                  icon: Icons.person_rounded,
                                  iconColor: _rose,
                                  label: "Display Name",
                                  value: _name,
                                  helperText: "Visible across all chats and calls",
                                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 20),
                                  onTap: _showEditNameSheet,
                                ),
                                _divider(),
                                _buildProfileTile(
                                  icon: Icons.format_quote_rounded,
                                  iconColor: _violet,
                                  label: "Bio / Note",
                                  value: _bio,
                                  helperText: "A short status or inside joke",
                                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 20),
                                  onTap: _showEditBioSheet,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // ── Group 2: Personal Details ─────────────────
                            _buildGroupCard(
                              title: "PERSONAL DETAILS",
                              children: [
                                _buildProfileTile(
                                  icon: Icons.cake_rounded,
                                  iconColor: Colors.amber,
                                  label: "Birthday",
                                  value: _formatBirthdayDisplay(_birthday),
                                  helperText: "Tap to select your birth date",
                                  trailing: const Icon(Icons.calendar_month_rounded, color: Colors.white30, size: 18),
                                  onTap: _pickBirthday,
                                ),
                                _divider(),
                                _buildProfileTile(
                                  icon: Icons.alternate_email_rounded,
                                  iconColor: Colors.blueAccent,
                                  label: "Email Address",
                                  value: _userEmail ?? "Not available",
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.25)),
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
                                  onTap: () {},
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // ── Group 3: Private Channel Status ───────────
                            _buildGroupCard(
                              title: "SPACE DETAILS",
                              children: [
                                _buildProfileTile(
                                  icon: Icons.favorite_rounded,
                                  iconColor: _rose,
                                  label: "Relationship Space",
                                  value: _partnerName != null ? "Coupled with $_partnerName" : "Solo Channel",
                                  helperText: "End-to-End Encrypted space",
                                  trailing: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _partnerName != null ? Colors.greenAccent : Colors.white38,
                                      boxShadow: _partnerName != null
                                          ? [
                                              BoxShadow(
                                                color: Colors.greenAccent.withValues(alpha: 0.6),
                                                blurRadius: 6,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                  onTap: () {},
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  // ── Inset Group Container ──────────────────────────────────────────────────
  Widget _buildGroupCard({required String title, required List<Widget> children}) {
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  // ── Profile Tile Row ───────────────────────────────────────────────────────
  Widget _buildProfileTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    String? helperText,
    Widget? trailing,
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
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
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value.isNotEmpty ? value : "Not set",
                    style: TextStyle(
                      color: value.isNotEmpty ? Colors.white : Colors.white30,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontStyle: value.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                  if (helperText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      helperText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.05),
        margin: const EdgeInsets.only(left: 60, right: 16),
      );
}