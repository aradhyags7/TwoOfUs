import 'package:flutter/material.dart';
import '../models/media.dart';
import '../services/api_service.dart';
import '../services/security_service.dart';
import '../theme/theme_controller.dart';
import 'chat_media_bubble.dart';

class FullScreenImageViewer extends StatefulWidget {
  final int mediaId;
  final String token;
  final String? title;
  final MediaItem? media;

  const FullScreenImageViewer({
    super.key,
    required this.mediaId,
    required this.token,
    this.title,
    this.media,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    if (widget.media?.isViewOnce == true) {
      SecurityService.enableSecureScreen();
    }
  }

  @override
  void dispose() {
    if (widget.media?.isViewOnce == true) {
      SecurityService.disableSecureScreen();
    }
    _transformationController.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      _transformationController.value = Matrix4.identity()..scaleByDouble(2.5, 2.5, 1.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiService.getMediaFileUrl(widget.mediaId);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onDoubleTap: _onDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.8,
              maxScale: 4.0,
              child: Center(
                child: AuthenticatedImage(
                  url: imageUrl,
                  token: widget.token,
                  fit: BoxFit.contain,
                  media: widget.media,
                ),
              ),
            ),
          ),

          // Top Header Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black87, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title ?? "Photo Viewer",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.media != null && widget.media!.isViewOnce)
                    Builder(
                      builder: (context) {
                        final theme = ThemeController.currentTheme.value;
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.accentFill,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.border),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined, color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text(
                                "View Once",
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  if (widget.media != null && widget.media!.isEncrypted)
                    Builder(
                      builder: (context) {
                        final theme = ThemeController.currentTheme.value;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.surfaceRaised,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded, color: theme.accentBright, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                "E2EE",
                                style: TextStyle(color: theme.accentBright, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
