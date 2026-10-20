import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../utils/session.dart';
import '../widgets/design_system/app_avatar.dart';
import '../widgets/design_system/app_button.dart';
import '../widgets/design_system/app_sheet.dart';
import '../widgets/design_system/app_text_field.dart';
import '../widgets/design_system/section_group.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — User Profile Screen (Design System)
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int? _userId;
  String _name = "";
  String _bio = "";
  String _birthday = "";
  String? _userEmail;
  String? _avatarUrl;
  File? _localAvatarFile;

  bool _loading = true;
  bool _uploadingAvatar = false;
  int _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;

  final ScrollController _scrollController = ScrollController();
  bool _showCollapsedTitle = false;

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
    final show = _scrollController.hasClients && _scrollController.offset > 80;
    if (show != _showCollapsedTitle) {
      setState(() => _showCollapsedTitle = show);
    }
  }

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
    AppSheet.show(
      context: context,
      builder: (ctx) => AppSheet(
        title: "Profile Photo",
        subtitle: "Customize your avatar image",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_avatarUrl != null || _localAvatarFile != null) ...[
              AppListTile(
                icon: Icons.fullscreen_rounded,
                title: "View Full Photo",
                subtitle: "Inspect high-resolution image",
                onTap: () {
                  Navigator.pop(ctx);
                  _openAvatarLightbox();
                },
              ),
            ],
            AppListTile(
              icon: Icons.camera_alt_rounded,
              title: "Take Photo",
              subtitle: "Capture with device camera",
              onTap: () => _pickAndUploadAvatar(ImageSource.camera),
            ),
            AppListTile(
              icon: Icons.photo_library_rounded,
              title: "Choose from Gallery",
              subtitle: "Select existing picture",
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
      builder: (ctx) {
        final theme = ThemeController.currentTheme.value;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: Icon(Icons.close_rounded, color: theme.textPrimary, size: 28),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  child: Image(
                    image: imageProvider,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppButton(
                text: "Change Photo",
                variant: AppButtonVariant.secondary,
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAvatarOptionsSheet();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditNameSheet() {
    final ctrl = TextEditingController(text: _name);
    bool isSaving = false;

    AppSheet.show(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return AppSheet(
            title: "Edit Display Name",
            subtitle: "This name is visible in your conversations and calls.",
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: "Display Name",
                  controller: ctrl,
                  prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                  hintText: "Enter your name",
                  autofocus: true,
                ),
                const SizedBox(height: 20),
                AppButton(
                  text: "Save Changes",
                  isFullWidth: true,
                  isLoading: isSaving,
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
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditBioSheet() {
    final ctrl = TextEditingController(text: _bio);
    bool isSaving = false;

    AppSheet.show(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return AppSheet(
            title: "Edit Status / Bio",
            subtitle: "A short note or inside joke shared with your partner.",
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: "Bio / Status",
                  controller: ctrl,
                  prefixIcon: const Icon(Icons.format_quote_rounded, size: 20),
                  hintText: "What's on your mind?",
                  maxLines: 3,
                  autofocus: true,
                ),
                const SizedBox(height: 20),
                AppButton(
                  text: "Save Status",
                  isFullWidth: true,
                  isLoading: isSaving,
                  onPressed: isSaving
                      ? null
                      : () async {
                          final newBio = ctrl.text.trim();
                          setSheetState(() => isSaving = true);
                          final ok = await ApiService.updateProfile(_userId!, _name, newBio, _birthday);
                          if (!ctx.mounted) return;
                          if (ok) {
                            if (!mounted) return;
                            setState(() => _bio = newBio);
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                            AppFeedback.showSuccess(context, "Status updated.");
                          } else {
                            setSheetState(() => isSaving = false);
                            if (ctx.mounted) AppFeedback.showError(ctx, "Failed to update status.");
                          }
                        },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickBirthday(AppTheme activeTheme) async {
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
        data: (activeTheme.isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
          colorScheme: (activeTheme.isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
            primary: activeTheme.accentFill,
            onPrimary: activeTheme.onAccent,
            surface: activeTheme.surface,
            onSurface: activeTheme.textPrimary,
          ),
          dialogTheme: DialogThemeData(backgroundColor: activeTheme.bg),
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
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: activeTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: AnimatedOpacity(
              opacity: _showCollapsedTitle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Text(
                _name.isNotEmpty ? _name : "Profile",
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: activeTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: Icon(Icons.edit_outlined, color: activeTheme.textSecondary, size: 20),
                tooltip: "Edit Name",
                onPressed: _showEditNameSheet,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: activeTheme.accentFill,
                    strokeWidth: 2.5,
                  ),
                )
              : SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      // Avatar & Identity Header
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _showAvatarOptionsSheet,
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: activeTheme.border, width: 2),
                                    ),
                                    child: _localAvatarFile != null
                                        ? ClipOval(
                                            child: Image.file(
                                              _localAvatarFile!,
                                              width: 92,
                                              height: 92,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : AppAvatar(
                                            name: _name.isNotEmpty ? _name : "TwoOfUs",
                                            imageUrl: _avatarUrl != null && _avatarUrl!.isNotEmpty
                                                ? (_avatarUrl!.startsWith('http')
                                                    ? "${_avatarUrl!}?v=$_avatarCacheKey"
                                                    : "${ApiService.baseUrl}/${_avatarUrl!.startsWith('/') ? _avatarUrl!.substring(1) : _avatarUrl!}?v=$_avatarCacheKey")
                                                : null,
                                            size: 92,
                                          ),
                                  ),
                                  if (_uploadingAvatar)
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.black.withValues(alpha: 0.5),
                                        ),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: activeTheme.accentFill,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: activeTheme.bg, width: 2),
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.camera_alt_rounded,
                                        color: activeTheme.onAccent,
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
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: activeTheme.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Handle Chip with Tap-to-Copy
                            GestureDetector(
                              onTap: () {
                                final text = "@${_name.isNotEmpty ? _name.toLowerCase().replaceAll(' ', '_') : 'username'}";
                                Clipboard.setData(ClipboardData(text: text));
                                HapticFeedback.lightImpact();
                                AppFeedback.showSuccess(context, "Copied $text to clipboard");
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: activeTheme.surfaceRaised,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: activeTheme.border, width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "@${_name.isNotEmpty ? _name.toLowerCase().replaceAll(' ', '_') : "username"}",
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: activeTheme.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.copy_rounded,
                                      color: activeTheme.textTertiary,
                                      size: 12,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Section 1: Profile Info
                      SectionGroup(
                        title: "PROFILE INFO",
                        children: [
                          AppListTile(
                            icon: Icons.person_outline_rounded,
                            title: _name.isNotEmpty ? _name : "Set display name",
                            subtitle: "Display Name",
                            showChevron: true,
                            onTap: _showEditNameSheet,
                          ),
                          AppListTile(
                            icon: Icons.format_quote_rounded,
                            title: _bio.isNotEmpty ? _bio : "Add bio or status...",
                            subtitle: "Bio / Note",
                            showChevron: true,
                            onTap: _showEditBioSheet,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Section 2: Personal Details
                      SectionGroup(
                        title: "PERSONAL DETAILS",
                        children: [
                          AppListTile(
                            icon: Icons.cake_outlined,
                            title: _formatBirthdayDisplay(_birthday),
                            subtitle: "Birthday",
                            trailing: Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                              color: activeTheme.textTertiary,
                            ),
                            onTap: () => _pickBirthday(activeTheme),
                          ),
                          AppListTile(
                            icon: Icons.alternate_email_rounded,
                            title: _userEmail ?? "Not available",
                            subtitle: "Email Address",
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: activeTheme.success.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: activeTheme.success.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                "Verified",
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: activeTheme.success,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            onTap: () {},
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
        );
      },
    );
  }
}