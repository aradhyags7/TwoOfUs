import 'package:flutter/material.dart';
import '../models/media.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/chat_media_bubble.dart';
import '../widgets/design_system/empty_state.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../widgets/video_player_dialog.dart';

class MediaGalleryScreen extends StatefulWidget {
  final int partnerId;
  final String partnerName;
  final String token;

  const MediaGalleryScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
    required this.token,
  });

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<MediaItem> _photos = [];
  List<MediaItem> _videos = [];
  List<MediaItem> _docs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchPairGallery();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchPairGallery() async {
    setState(() => _isLoading = true);
    final rawList = await ApiService.getPairMediaGallery(
      widget.partnerId,
      widget.token,
      limit: 50,
      offset: 0,
    );

    final items = rawList.map((e) => MediaItem.fromJson(e)).toList();
    if (mounted) {
      setState(() {
        _photos = items.where((m) => m.isImage).toList();
        _videos = items.where((m) => m.isVideo).toList();
        _docs = items.where((m) => m.isFile).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        final accentColor = activeTheme.isDark ? activeTheme.accentBright : activeTheme.accentFill;

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
            title: Text(
              "Shared Media",
              style: TextStyle(
                fontFamily: 'Inter',
                color: activeTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: activeTheme.border, width: 1)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: accentColor,
                  indicatorWeight: 2.5,
                  labelColor: accentColor,
                  unselectedLabelColor: activeTheme.textTertiary,
                  labelStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: [
                    Tab(text: "Photos (${_photos.length})"),
                    Tab(text: "Videos (${_videos.length})"),
                    Tab(text: "Docs (${_docs.length})"),
                  ],
                ),
              ),
            ),
          ),
          body: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: activeTheme.accentFill,
                    strokeWidth: 2.5,
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPhotosGrid(activeTheme),
                    _buildVideosGrid(activeTheme),
                    _buildDocsList(activeTheme),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildPhotosGrid(AppTheme theme) {
    if (_photos.isEmpty) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: "No Shared Photos",
        description: "Photos shared in this conversation will be cataloged here.",
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
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final item = _photos[index];
        final thumbUrl = ApiService.getMediaThumbnailUrl(item.id);
        final fullUrl = ApiService.getMediaFileUrl(item.id);

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenImageViewer(
                  media: item,
                  mediaId: item.id,
                  token: widget.token,
                  title: item.originalFilename,
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.border, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AuthenticatedImage(
                  url: thumbUrl,
                  fallbackUrl: fullUrl,
                  token: widget.token,
                  media: item,
                ),
                if (item.isEncrypted)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        color: theme.isDark ? theme.accentBright : theme.accentFill,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideosGrid(AppTheme theme) {
    if (_videos.isEmpty) {
      return const EmptyState(
        icon: Icons.videocam_outlined,
        title: "No Shared Videos",
        description: "Videos shared in this conversation will be cataloged here.",
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.3,
      ),
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final item = _videos[index];
        final videoUrl = ApiService.getMediaFileUrl(item.id);

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerDialog(
                  media: item,
                  videoUrl: videoUrl,
                  token: widget.token,
                  title: item.originalFilename,
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: theme.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.border, width: 1),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.border, width: 1),
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: theme.isDark ? theme.accentBright : theme.accentFill,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        item.originalFilename,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: theme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (item.isEncrypted)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        color: theme.isDark ? theme.accentBright : theme.accentFill,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocsList(AppTheme theme) {
    if (_docs.isEmpty) {
      return const EmptyState(
        icon: Icons.description_outlined,
        title: "No Shared Documents",
        description: "Documents and files exchanged will be displayed here.",
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: _docs.length,
      itemBuilder: (context, index) {
        final item = _docs[index];
        return ChatMediaBubble(
          media: item,
          token: widget.token,
          isMe: false,
        );
      },
    );
  }
}
