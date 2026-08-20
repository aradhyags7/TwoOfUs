import 'package:flutter/material.dart';
import '../models/media.dart';
import '../services/api_service.dart';
import '../widgets/chat_media_bubble.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFF141218),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1C24),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          "Shared Media with ${widget.partnerName}",
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.pinkAccent,
          labelColor: Colors.pinkAccent,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: "Photos (${_photos.length})"),
            Tab(text: "Videos (${_videos.length})"),
            Tab(text: "Docs (${_docs.length})"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.pinkAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPhotosGrid(),
                _buildVideosGrid(),
                _buildDocsList(),
              ],
            ),
    );
  }

  Widget _buildPhotosGrid() {
    if (_photos.isEmpty) {
      return const Center(
        child: Text("No shared photos yet 🖼️", style: TextStyle(color: Colors.grey)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AuthenticatedImage(
                  url: thumbUrl,
                  fallbackUrl: fullUrl,
                  token: widget.token,
                  media: item,
                ),
              ),
              if (item.isEncrypted)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_rounded, color: Colors.pinkAccent, size: 10),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideosGrid() {
    if (_videos.isEmpty) {
      return const Center(
        child: Text("No shared videos yet 🎥", style: TextStyle(color: Colors.grey)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
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
              color: Colors.purpleAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
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
                      decoration: const BoxDecoration(
                        color: Colors.white30,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        item.originalFilename,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
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
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_rounded, color: Colors.pinkAccent, size: 10),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocsList() {
    if (_docs.isEmpty) {
      return const Center(
        child: Text("No shared documents yet 📄", style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
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
