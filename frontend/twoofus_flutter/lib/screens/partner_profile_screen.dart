import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import '../widgets/chat_media_bubble.dart';
import '../widgets/encryption_verification_modal.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../widgets/video_player_dialog.dart';
import 'media_gallery_screen.dart';
import 'theme_selection_screen.dart';

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
  bool get _isDark => ThemeController.currentTheme.value.textPrimary == Colors.white;

  Color get _text => _isDark ? Colors.white : const Color(0xFF1A0A2E);
  Color get _sub => _isDark
      ? Colors.white.withValues(alpha: 0.48)
      : Colors.black.withValues(alpha: 0.45);
  Color get _border => _isDark
      ? ThemeController.currentTheme.value.border
      : Colors.black.withValues(alpha: 0.08);

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
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? const Color(0xFF3D0017) : _violet,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      ),
    );
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
              // Collapsible Hero Header
              SliverAppBar(
                expandedHeight: 310.0,
                pinned: true,
                backgroundColor: _surf,
                elevation: 0,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 20),
                    ),
                    onPressed: () {
                      _fetchPartnerProfile();
                      _fetchMediaGallery();
                      _toast("Refreshed partner info & media ❤️");
                    },
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.more_vert_rounded,
                          color: Colors.white, size: 20),
                    ),
                    onPressed: _showMoreOptionsMenu,
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Gradient Cover Background
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_rose, _violet, _bg],
                          ),
                        ),
                      ),
                      // Glass Overlay
                      Container(color: Colors.black.withValues(alpha: 0.25)),

                      // Main Header Content
                      Positioned(
                        bottom: 24,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Avatar
                            GestureDetector(
                              onTap: () => _openAvatarLightbox(avatarUrl, username),
                              child: Hero(
                                tag: 'partner_avatar_${widget.partnerId}',
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [_rose, _lavender],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: avatarUrl != null && avatarUrl.isNotEmpty
                                      ? ClipOval(
                                          child: Image.network(
                                            avatarUrl.startsWith('http')
                                                ? avatarUrl
                                                : "${ApiService.baseUrl}/${avatarUrl.startsWith('/') ? avatarUrl.substring(1) : avatarUrl}",
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _avatarFallback(username),
                                          ),
                                        )
                                      : _avatarFallback(username),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Partner Name
                            Text(
                              username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Status Badge
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: widget.isOnline
                                        ? Colors.greenAccent
                                        : Colors.white54,
                                    boxShadow: widget.isOnline
                                        ? [
                                            BoxShadow(
                                              color: Colors.greenAccent
                                                  .withValues(alpha: 0.6),
                                              blurRadius: 6,
                                              spreadRadius: 1,
                                            )
                                          ]
                                        : [],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  widget.isOnline ? "Online now" : "Offline",
                                  style: TextStyle(
                                    color: widget.isOnline
                                        ? Colors.greenAccent
                                        : Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Quick Action Bar (Audio, Video, Media Vault, Mute)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _surf,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _actionBtn(
                          icon: Icons.call_rounded,
                          label: "Audio",
                          onTap: () => _toast("Calling $username... 📞"),
                        ),
                        _actionBtn(
                          icon: Icons.videocam_rounded,
                          label: "Video",
                          onTap: () => _toast("Starting video call... 📹"),
                        ),
                        _actionBtn(
                          icon: Icons.photo_library_rounded,
                          label: "Vault",
                          onTap: _openMediaVaultFull,
                        ),
                        _actionBtn(
                          icon: _muted
                              ? Icons.notifications_off_rounded
                              : Icons.notifications_active_rounded,
                          label: _muted ? "Unmute" : "Mute",
                          color: _muted ? Colors.orangeAccent : _rose,
                          onTap: () {
                            setState(() => _muted = !_muted);
                            _toast(
                              _muted
                                  ? "Muted notifications for $username 🔕"
                                  : "Unmuted notifications for $username 🔔",
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // About & Information Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _surf,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ShaderMask(
                              shaderCallback: (b) =>
                                  LinearGradient(colors: [_rose, _violet])
                                      .createShader(b),
                              blendMode: BlendMode.srcIn,
                              child: const Icon(Icons.info_outline_rounded,
                                  size: 20, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "About & Info",
                              style: TextStyle(
                                color: _text,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Bio
                        _infoTile(
                          icon: Icons.notes_rounded,
                          title: _loading
                              ? "Loading profile info..."
                              : (bio.isNotEmpty ? bio : "No bio added yet ❤️"),
                          subtitle: "Bio",
                        ),

                        if (email.isNotEmpty) ...[
                          const Divider(height: 20),
                          _infoTile(
                            icon: Icons.email_outlined,
                            title: email,
                            subtitle: "Email",
                          ),
                        ],

                        if (birthday.isNotEmpty) ...[
                          const Divider(height: 20),
                          _infoTile(
                            icon: Icons.cake_outlined,
                            title: birthday,
                            subtitle: "Birthday / Special Date",
                          ),
                        ],

                        const Divider(height: 20),
                        _infoTile(
                          icon: Icons.alternate_email_rounded,
                          title: "@${username.toLowerCase().replaceAll(' ', '_')}",
                          subtitle: "Username",
                          onTap: () {
                            Clipboard.setData(ClipboardData(
                                text: "@${username.toLowerCase()}"));
                            _toast("Username copied to clipboard 📋");
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Shared Media Tabs Title & Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _surf,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      border: Border.all(color: _border),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: _rose,
                      indicatorWeight: 3,
                      labelColor: _rose,
                      unselectedLabelColor: _sub,
                      labelStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
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
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
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
                        // Media Grid Tab
                        _buildMediaTab(),
                        // Links Tab
                        _buildLinksTab(),
                        // Docs Tab
                        _buildDocsTab(),
                        // Memories Tab
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _surf,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      children: [
                        _settingRow(
                          icon: Icons.palette_outlined,
                          title: "Chat Theme & Wallpaper",
                          subtitle: "Personalize chat background and colors",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ThemeSelectionScreen(),
                              ),
                            );
                          },
                        ),
                        Divider(height: 1, color: _border),
                        _settingRow(
                          icon: Icons.verified_user_rounded,
                          title: "Encryption & Safety Code",
                          subtitle: "Verify 60-digit security safety code 🔒",
                          iconColor: Colors.pinkAccent,
                          onTap: () => EncryptionVerificationModal.show(
                            context,
                            partnerId: widget.partnerId,
                            partnerName: username,
                          ),
                        ),
                        Divider(height: 1, color: _border),
                        _settingRow(
                          icon: Icons.cleaning_services_rounded,
                          title: "Clear Chat History",
                          subtitle: "Delete local messages with $username",
                          iconColor: Colors.amberAccent,
                          onTap: _showClearChatDialog,
                        ),
                        Divider(height: 1, color: _border),
                        _settingRow(
                          icon: Icons.block_rounded,
                          title: "Block / Unpair Partner",
                          subtitle: "Disconnect from this pair connection",
                          iconColor: Colors.redAccent,
                          titleColor: Colors.redAccent,
                          onTap: _showBlockPartnerDialog,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Avatar Fallback ────────────────────────────────────────────────────────
  Widget _avatarFallback(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : "P";
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          const Icon(Icons.favorite_rounded, color: Colors.white70, size: 16),
        ],
      ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: btnColor.withValues(alpha: 0.12),
              border: Border.all(color: btnColor.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: btnColor, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: _text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Info Tile Item ────────────────────────────────────────────────────────
  Widget _infoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _rose.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _rose, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _sub,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.copy_rounded, color: _sub, size: 16),
          ],
        ),
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
        message: "No shared photos or videos yet ❤️",
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
      separatorBuilder: (_, __) => Divider(height: 12, color: _border),
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
      separatorBuilder: (_, __) => Divider(height: 12, color: _border),
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
        icon: Icons.favorite_border_rounded,
        message: "No special memories saved yet ❤️",
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      physics: const BouncingScrollPhysics(),
      itemCount: widget.memories.length,
      separatorBuilder: (_, __) => Divider(height: 12, color: _border),
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
            child: Icon(Icons.favorite_rounded, color: _rose, size: 18),
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

  // ── Settings Tile Row ─────────────────────────────────────────────────────
  Widget _settingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    final color = iconColor ?? _rose;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? _text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: _sub, fontSize: 11),
      ),
      trailing: Icon(Icons.arrow_forward_ios_rounded, color: _sub, size: 14),
      onTap: onTap,
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
            Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [_rose, _violet]),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 20),
                ],
              ),
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        avatarUrl.startsWith('http')
                            ? avatarUrl
                            : "${ApiService.baseUrl}/${avatarUrl.startsWith('/') ? avatarUrl.substring(1) : avatarUrl}",
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(username),
                      ),
                    )
                  : _avatarFallback(username),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: _surf,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: _rose),
              title: Text("Open Shared Media Vault", style: TextStyle(color: _text)),
              onTap: () {
                Navigator.pop(ctx);
                _openMediaVaultFull();
              },
            ),
            ListTile(
              leading: Icon(Icons.share_rounded, color: _rose),
              title: Text("Share Contact", style: TextStyle(color: _text)),
              onTap: () {
                Navigator.pop(ctx);
                _toast("Contact link copied 📲");
              },
            ),
            ListTile(
              leading: Icon(Icons.shortcut_rounded, color: _violet),
              title: Text("Add Shortcut to Home Screen", style: TextStyle(color: _text)),
              onTap: () {
                Navigator.pop(ctx);
                _toast("Shortcut added to home screen ⭐");
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Clear Chat History?", style: TextStyle(color: _text)),
        content: Text(
          "Are you sure you want to permanently delete all messages and media with ${widget.partnerName} from the database?",
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
                _toast("Chat history cleared from database 🧹");
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
            child: const Text("Clear", style: TextStyle(color: Colors.redAccent)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Unpair / Block ${widget.partnerName}?", style: TextStyle(color: _text)),
        content: Text(
          "This will disconnect your pair relationship with ${widget.partnerName}.",
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
            child: const Text("Unpair", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
