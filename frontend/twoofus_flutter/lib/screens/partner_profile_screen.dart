import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../utils/session.dart';
import '../widgets/chat_media_bubble.dart';
import '../widgets/encryption_verification_modal.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../widgets/video_player_dialog.dart';
import '../services/call_service.dart';
import 'media_gallery_screen.dart';
import 'theme_selection_screen.dart';
import '../widgets/design_system/design_system.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — PartnerProfileScreen (Telegram / WhatsApp Style)
// ─────────────────────────────────────────────────────────────────────────────

class PartnerProfileScreen extends StatefulWidget {
  final int partnerId;
  final String partnerName;
  final bool isOnline;
  final List<Message> messages;
  final List<dynamic> memories;

  const PartnerProfileScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
    this.isOnline = true,
    this.messages = const [],
    this.memories = const [],
  });

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _loadingMedia = true;
  bool _muted = false;
  Map<String, dynamic>? _profileData;
  String _userToken = '';

  late TabController _tabController;

  // Extracted lists from API & messages
  List<MediaItem> _galleryMedia = [];
  List<MediaItem> _photos = [];
  List<MediaItem> _videos = [];
  List<MediaItem> _docs = [];
  List<String> _sharedLinks = [];
  List<Message> _docMessages = [];

  // ── Palette ────────────────────────────────────────────────────────────────
  Color get _bg => ThemeController.currentTheme.value.bg;
  Color get _surf => ThemeController.currentTheme.value.surface;
  Color get _rose => ThemeController.currentTheme.value.primary;
  Color get _violet => ThemeController.currentTheme.value.secondary;
  Color get _lavender => ThemeController.currentTheme.value.gradientEnd;
  bool get _isDark => ThemeController.currentTheme.value.bg.computeLuminance() < 0.5;

  Color get _text => ThemeController.currentTheme.value.textPrimary;
  Color get _sub => ThemeController.currentTheme.value.textMuted;
  Color get _border => ThemeController.currentTheme.value.border;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _extractSharedContent();
    _fetchPartnerProfile();
    _fetchMediaGallery();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data Loading & Extraction ──────────────────────────────────────────────
  Future<void> _fetchPartnerProfile() async {
    final data = await ApiService.getProfile(widget.partnerId);
    if (mounted) {
      setState(() {
        _profileData = data;
        _loading = false;
      });
    }
  }

  Future<void> _fetchMediaGallery() async {
    try {
      final token = await Session.getToken() ?? '';
      _userToken = token;
      final rawList = await ApiService.getPairMediaGallery(
        widget.partnerId,
        token,
        limit: 100,
        offset: 0,
      );

      final items = rawList.map((e) => MediaItem.fromJson(e)).toList();
      if (mounted) {
        setState(() {
          _galleryMedia = items;
          _photos = items.where((m) => m.isImage).toList();
          _videos = items.where((m) => m.isVideo).toList();
          _docs = items.where((m) => m.isFile).toList();
          _loadingMedia = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMedia = false);
      }
    }
  }

  void _extractSharedContent() {
    final linkRegex = RegExp(
      r'https?://[^\s/$.?#].[^\s]*',
      caseSensitive: false,
    );

    List<String> links = [];
    List<Message> docs = [];

    for (var m in widget.messages) {
      // Check for web links
      final matches = linkRegex.allMatches(m.content);
      for (var match in matches) {
        final url = match.group(0);
        if (url != null && !links.contains(url)) {
          links.add(url);
        }
      }

      // Check for docs / long notes / code attachments
      if (m.content.length > 120 ||
          m.content.contains("```") ||
          m.content.contains("http://") ||
          m.content.contains("https://")) {
        docs.add(m);
      }
    }

    _sharedLinks = links;
    _docMessages = docs;
  }

  void _toast(String msg, {bool isError = false}) {
    if (isError) {
      AppFeedback.showError(context, msg);
    } else {
      AppFeedback.showSuccess(context, msg);
    }
  }

  void _openMediaVaultFull() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaGalleryScreen(
          partnerId: widget.partnerId,
          partnerName: widget.partnerName,
          token: _userToken,
        ),
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        final avatarUrl = _profileData?['avatar_url'];
        final username = _profileData?['username'] ?? widget.partnerName;
        final bio = _profileData?['bio'] ?? '';
        final email = _profileData?['email'] ?? '';
        final birthday = _profileData?['birthday'] ?? '';
        final totalMediaCount = _photos.length + _videos.length;

        return Scaffold(
          backgroundColor: _bg,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Clean Header
              SliverAppBar(
                expandedHeight: 220.0,
                pinned: true,
                backgroundColor: _surf,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: _text, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: _text, size: 20),
                    onPressed: () {
                      _fetchPartnerProfile();
                      _fetchMediaGallery();
                      _toast("Refreshed partner profile & media");
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert_rounded, color: _text, size: 20),
                    onPressed: _showMoreOptionsMenu,
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    color: _surf,
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _openAvatarLightbox(avatarUrl, username),
                            child: Hero(
                              tag: 'partner_avatar_${widget.partnerId}',
                              child: AppAvatar(
                                name: username,
                                imageUrl: avatarUrl,
                                size: 80,
                                isOnline: widget.isOnline,
                                showOnlineIndicator: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            username,
                            style: TextStyle(
                              color: _text,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.isOnline ? "Online" : "Offline",
                            style: TextStyle(
                              color: widget.isOnline
                                  ? (_isDark ? AppColors.darkSuccess : AppColors.lightSuccess)
                                  : _sub,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Quick Action Bar (Audio, Video, Media Vault, Mute)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _surf,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _actionBtn(
                            icon: Icons.call_outlined,
                            label: "Audio",
                            onTap: () {
                              CallService.startCall(
                                context: context,
                                partnerId: widget.partnerId,
                                partnerName: username,
                                callType: 'voice',
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: _actionBtn(
                            icon: Icons.videocam_outlined,
                            label: "Video",
                            onTap: () {
                              CallService.startCall(
                                context: context,
                                partnerId: widget.partnerId,
                                partnerName: username,
                                callType: 'video',
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: _actionBtn(
                            icon: Icons.photo_library_outlined,
                            label: "Vault",
                            onTap: _openMediaVaultFull,
                          ),
                        ),
                        Expanded(
                          child: _actionBtn(
                            icon: _muted
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_outlined,
                            label: _muted ? "Unmute" : "Mute",
                            color: _muted ? AppColors.darkWarning : null,
                            onTap: () {
                              setState(() => _muted = !_muted);
                              _toast(
                                _muted
                                    ? "Muted notifications for $username"
                                    : "Unmuted notifications for $username",
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // About & Information Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SectionGroup(
                    title: "About",
                    children: [
                      AppListTile(
                        icon: Icons.notes_rounded,
                        title: _loading
                            ? "Loading profile info..."
                            : (bio.isNotEmpty ? bio : "No bio added yet"),
                        subtitle: "Bio",
                      ),
                      if (email.isNotEmpty)
                        AppListTile(
                          icon: Icons.email_outlined,
                          title: email,
                          subtitle: "Email",
                        ),
                      if (birthday.isNotEmpty)
                        AppListTile(
                          icon: Icons.cake_outlined,
                          title: birthday,
                          subtitle: "Birthday / Special Date",
                        ),
                      AppListTile(
                        icon: Icons.alternate_email_rounded,
                        title: "@${username.toLowerCase().replaceAll(' ', '_')}",
                        subtitle: "Username",
                        trailing: Icon(Icons.copy_rounded, color: _sub, size: 16),
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                              text: "@${username.toLowerCase()}"));
                          _toast("Username copied to clipboard");
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Shared Media Tabs Title & Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _surf,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      border: Border.all(color: _border),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorColor: _rose,
                      indicatorWeight: 2,
                      labelColor: _rose,
                      unselectedLabelColor: _sub,
                      labelStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      unselectedLabelStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.normal),
                      tabs: [
                        Tab(text: "Media ($totalMediaCount)"),
                        Tab(text: "Links (${_sharedLinks.length})"),
                        Tab(text: "Docs (${_docs.length + _docMessages.length})"),
                        Tab(text: "Memories (${widget.memories.length})"),
                      ],
                    ),
                  ),
                ),
              ),

              // Shared Content Tab Content View
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    height: 310,
                    decoration: BoxDecoration(
                      color: _surf,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border(
                        left: BorderSide(color: _border),
                        right: BorderSide(color: _border),
                        bottom: BorderSide(color: _border),
                      ),
                    ),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildMediaTab(),
                        _buildLinksTab(),
                        _buildDocsTab(),
                        _buildMemoriesTab(),
                      ],
                    ),
                  ),
                ),
              ),

              // Customization & Security Actions Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: SectionGroup(
                    title: "Settings & Privacy",
                    children: [
                      AppListTile(
                        icon: Icons.palette_outlined,
                        title: "Chat Theme & Wallpaper",
                        subtitle: "Personalize chat background and colors",
                        trailing: Icon(Icons.chevron_right_rounded, color: _sub, size: 20),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ThemeSelectionScreen(),
                            ),
                          );
                        },
                      ),
                      AppListTile(
                        icon: Icons.verified_user_outlined,
                        title: "Encryption & Safety Code",
                        subtitle: "Verify 60-digit security safety code",
                        trailing: Icon(Icons.chevron_right_rounded, color: _sub, size: 20),
                        onTap: () => EncryptionVerificationModal.show(
                          context,
                          partnerId: widget.partnerId,
                          partnerName: username,
                        ),
                      ),
                      AppListTile(
                        icon: Icons.cleaning_services_outlined,
                        title: "Clear Chat History",
                        subtitle: "Delete local messages with $username",
                        onTap: _showClearChatDialog,
                      ),
                      AppListTile(
                        icon: Icons.block_outlined,
                        title: "Block / Unpair Partner",
                        subtitle: "Disconnect from this pair connection",
                        isDestructive: true,
                        onTap: _showBlockPartnerDialog,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Quick Action Button Item ───────────────────────────────────────────────
  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final btnColor = color ?? _rose;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isDark ? AppColors.darkSurfaceRaised : AppColors.lightSurfaceRaised,
              border: Border.all(color: _border),
            ),
            child: Icon(icon, color: btnColor, size: 20),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: _text,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared Content Tabs Implementation ────────────────────────────────────
  Widget _buildMediaTab() {
    if (_loadingMedia) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: _rose, strokeWidth: 2.2),
        ),
      );
    }

    final allVisualMedia = [..._photos, ..._videos];

    if (allVisualMedia.isEmpty) {
      return _emptyTabState(
        icon: Icons.photo_library_outlined,
        message: "No shared photos or videos yet",
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: allVisualMedia.length,
      itemBuilder: (ctx, index) {
        final item = allVisualMedia[index];
        final thumbUrl = ApiService.getMediaThumbnailUrl(item.id);
        final fullUrl = ApiService.getMediaFileUrl(item.id);

        return GestureDetector(
          onTap: () {
            if (item.isVideo) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoPlayerDialog(
                    media: item,
                    videoUrl: fullUrl,
                    token: _userToken,
                    title: item.originalFilename,
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenImageViewer(
                    media: item,
                    mediaId: item.id,
                    token: _userToken,
                    title: item.originalFilename,
                  ),
                ),
              );
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: _surf,
                  child: AuthenticatedImage(
                    url: thumbUrl,
                    fallbackUrl: fullUrl,
                    token: _userToken,
                    media: item,
                  ),
                ),
              ),
              if (item.isVideo)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                  ),
                ),
              if (item.isEncrypted)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock_rounded, color: _rose, size: 10),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLinksTab() {
    if (_sharedLinks.isEmpty) {
      return _emptyTabState(
        icon: Icons.link_rounded,
        message: "No links shared in chat yet 🔗",
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      physics: const BouncingScrollPhysics(),
      itemCount: _sharedLinks.length,
      separatorBuilder: (context, index) => Divider(height: 12, color: _border),
      itemBuilder: (ctx, index) {
        final link = _sharedLinks[index];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _violet.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.link_rounded, color: _violet, size: 18),
          ),
          title: Text(
            link,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.blueAccent,
              fontSize: 13,
              decoration: TextDecoration.underline,
            ),
          ),
          trailing: IconButton(
            icon: Icon(Icons.copy_rounded, color: _sub, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              _toast("Link copied to clipboard 📋");
            },
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: link));
            _toast("Link copied to clipboard 📋");
          },
        );
      },
    );
  }

  Widget _buildDocsTab() {
    final combinedDocs = [..._docs, ..._docMessages];

    if (combinedDocs.isEmpty) {
      return _emptyTabState(
        icon: Icons.insert_drive_file_outlined,
        message: "No shared documents or notes 📁",
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      physics: const BouncingScrollPhysics(),
      itemCount: combinedDocs.length,
      separatorBuilder: (context, index) => Divider(height: 12, color: _border),
      itemBuilder: (ctx, index) {
        final doc = combinedDocs[index];
        if (doc is MediaItem) {
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _lavender.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.description_rounded, color: _lavender, size: 18),
            ),
            title: Text(
              doc.originalFilename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              doc.formattedFileSize,
              style: TextStyle(color: _sub, fontSize: 11),
            ),
          );
        } else if (doc is Message) {
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _lavender.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.article_outlined, color: _lavender, size: 18),
            ),
            title: Text(
              doc.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _text, fontSize: 13),
            ),
            subtitle: Text(
              "${doc.createdAt.day}/${doc.createdAt.month}/${doc.createdAt.year}",
              style: TextStyle(color: _sub, fontSize: 11),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildMemoriesTab() {
    if (widget.memories.isEmpty) {
      return _emptyTabState(
        icon: Icons.auto_awesome_outlined,
        message: "No special memories saved yet",
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      physics: const BouncingScrollPhysics(),
      itemCount: widget.memories.length,
      separatorBuilder: (context, index) => Divider(height: 12, color: _border),
      itemBuilder: (ctx, index) {
        final mem = widget.memories[index];
        final text = mem.text ?? mem.toString();
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _rose.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bookmark_rounded, color: _rose, size: 18),
          ),
          title: Text(
            text,
            style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }

  Widget _emptyTabState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: _sub.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: _sub, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Dialogs & Lightboxes ──────────────────────────────────────────────────
  void _openAvatarLightbox(String? avatarUrl, String username) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            AppAvatar(
              name: username,
              imageUrl: avatarUrl,
              size: 200,
            ),
            const SizedBox(height: 16),
            Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreOptionsMenu() {
    AppSheet.show(
      context: context,
      builder: (ctx) => AppSheet(
        title: "Conversation Options",
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          AppListTile(
            icon: Icons.photo_library_outlined,
            title: "Open Shared Media Vault",
            onTap: () {
              Navigator.pop(context);
              _openMediaVaultFull();
            },
          ),
          AppListTile(
            icon: Icons.share_outlined,
            title: "Share Contact",
            onTap: () {
              Navigator.pop(context);
              _toast("Contact link copied");
            },
          ),
          AppListTile(
            icon: Icons.shortcut_outlined,
            title: "Add Shortcut to Home Screen",
            onTap: () {
              Navigator.pop(context);
              _toast("Shortcut added to home screen");
            },
          ),
        ],
      ),
    ),
  );
}

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surf,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _border)),
        title: Text("Clear Chat History?", style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
        content: Text(
          "Are you sure you want to permanently delete all messages and media with ${widget.partnerName}?",
          style: TextStyle(color: _sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: _sub)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final token = await Session.getToken();
              final success = await ApiService.clearConversation(widget.partnerId, token: token);
              if (success) {
                _toast("Chat history cleared");
                if (mounted) {
                  setState(() {
                    _galleryMedia.clear();
                    _photos.clear();
                    _videos.clear();
                    _docs.clear();
                    _sharedLinks.clear();
                    _docMessages.clear();
                  });
                }
              } else {
                _toast("Failed to clear chat history", isError: true);
              }
            },
            child: Text("Clear", style: TextStyle(color: _isDark ? AppColors.darkDanger : AppColors.lightDanger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showBlockPartnerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surf,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _border)),
        title: Text("Unpair / Block ${widget.partnerName}?", style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
        content: Text(
          "This will disconnect your connection with ${widget.partnerName}.",
          style: TextStyle(color: _sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: _sub)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _toast("Unpaired successfully", isError: true);
            },
            child: Text("Unpair", style: TextStyle(color: _isDark ? AppColors.darkDanger : AppColors.lightDanger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
