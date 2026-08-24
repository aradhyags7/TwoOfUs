import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../models/media.dart';
import '../services/api_service.dart';
import '../services/e2ee_service.dart';
import '../utils/session.dart';
import 'full_screen_image_viewer.dart';
import 'video_player_dialog.dart';
import 'view_once_badge.dart';

class ChatMediaBubble extends StatefulWidget {
  final MediaItem media;
  final String token;
  final bool isMe;

  const ChatMediaBubble({
    super.key,
    required this.media,
    required this.token,
    required this.isMe,
  });

  @override
  State<ChatMediaBubble> createState() => _ChatMediaBubbleState();
}

class _ChatMediaBubbleState extends State<ChatMediaBubble> {
  bool _hasViewed = false;

  Future<void> _openDocument(BuildContext context) async {
    final fileUrl = ApiService.getMediaFileUrl(widget.media.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ${widget.media.originalFilename}...')),
    );

    try {
      final effectiveToken = widget.token.isNotEmpty ? widget.token : (await Session.getToken() ?? '');
      final rawBytes = await ApiService.fetchAuthenticatedBytes(fileUrl, effectiveToken);
      if (rawBytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to download document')),
          );
        }
        return;
      }

      Uint8List fileBytesToSave = rawBytes;
      if (widget.media.isEncrypted && widget.media.encryptedMediaKey != null && widget.media.encryptionNonce != null) {
        final myId = await Session.getUserId();
        final partnerId = (widget.media.senderId == myId) ? widget.media.receiverId : widget.media.senderId;
        final partnerPubKey = await E2EEService.getPartnerPublicKey(partnerId, token: effectiveToken);

        if (partnerPubKey != null && partnerPubKey.isNotEmpty) {
          final decrypted = await E2EEService.decryptMediaBytes(
            encryptedFileBytes: rawBytes,
            encryptedMediaKeyBundleJson: widget.media.encryptedMediaKey!,
            nonceBase64: widget.media.encryptionNonce!,
            remotePublicKeyBase64: partnerPubKey,
          );
          if (decrypted != null) {
            fileBytesToSave = decrypted;
          }
        }
      }

      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/${widget.media.originalFilename}');
      await tempFile.writeAsBytes(fileBytesToSave);

      if (await tempFile.exists()) {
        await OpenFilex.open(tempFile.path);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file: $e')),
        );
      }
    }
  }

  void _openViewOnceMedia() async {
    if (widget.media.isImage) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FullScreenImageViewer(
            media: widget.media,
            mediaId: widget.media.id,
            title: "View Once Photo",
            token: widget.token,
          ),
        ),
      );
    } else if (widget.media.isVideo) {
      final videoUrl = ApiService.getMediaFileUrl(widget.media.id);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerDialog(
            media: widget.media,
            videoUrl: videoUrl,
            title: "View Once Video",
            token: widget.token,
          ),
        ),
      );
    }
    if (mounted) {
      setState(() => _hasViewed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const rose = Color(0xFFFF2D75);
    const violet = Color(0xFF9B51E0);

    // ── 1. View Once Ephemeral Presentation ──────────────────────────────────
    final isConsumed = _hasViewed || widget.media.isExpired;

    if (widget.media.isViewOnce) {
      return GestureDetector(
        onTap: isConsumed ? null : _openViewOnceMedia,
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isConsumed
                ? Colors.white.withValues(alpha: 0.05)
                : (widget.isMe
                    ? rose.withValues(alpha: 0.22)
                    : violet.withValues(alpha: 0.22)),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isConsumed
                  ? Colors.white24
                  : (widget.isMe ? rose.withValues(alpha: 0.8) : violet.withValues(alpha: 0.8)),
              width: 1.5,
            ),
            boxShadow: isConsumed
                ? null
                : [
                    BoxShadow(
                      color: (widget.isMe ? rose : violet).withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ViewOnceBadge(
                isActive: !isConsumed,
                isOpened: isConsumed,
                size: 34,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.media.isVideo ? "View Once Video" : "View Once Photo",
                        style: TextStyle(
                          color: isConsumed ? Colors.white54 : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.media.isEncrypted) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.lock_rounded, color: Colors.pinkAccent, size: 12),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isConsumed ? "Opened • Expired" : "Confidential • Tap to reveal",
                    style: TextStyle(
                      color: isConsumed ? Colors.white38 : Colors.white70,
                      fontSize: 11,
                      fontWeight: isConsumed ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // ── 2. Standard Image ───────────────────────────────────────────────────
    if (widget.media.isImage) {
      final imageUrl = ApiService.getMediaFileUrl(widget.media.id);
      final thumbUrl = ApiService.getMediaThumbnailUrl(widget.media.id);

      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenImageViewer(
                media: widget.media,
                mediaId: widget.media.id,
                title: widget.media.originalFilename,
                token: widget.token,
              ),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 220),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AuthenticatedImage(
                  url: thumbUrl,
                  fallbackUrl: imageUrl,
                  token: widget.token,
                  media: widget.media,
                ),
              ),
              if (widget.media.isEncrypted)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_rounded, color: Colors.pinkAccent, size: 12),
                  ),
                ),
            ],
          ),
        ),
      );
    } else if (widget.media.isVideo) {
      // ── 3. Standard Video ─────────────────────────────────────────────────
      final videoUrl = ApiService.getMediaFileUrl(widget.media.id);

      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoPlayerDialog(
                media: widget.media,
                videoUrl: videoUrl,
                title: widget.media.originalFilename,
                token: widget.token,
              ),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          width: 220,
          height: 140,
          decoration: BoxDecoration(
            color: widget.isMe ? Colors.pinkAccent.withValues(alpha: 0.2) : Colors.purpleAccent.withValues(alpha: 0.2),
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
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: Colors.white30,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      widget.media.originalFilename,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    widget.media.formattedFileSize,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
              if (widget.media.isEncrypted)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_rounded, color: Colors.pinkAccent, size: 12),
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      // ── 4. Document Card ──────────────────────────────────────────────────
      return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isMe ? Colors.pinkAccent.withValues(alpha: 0.15) : Colors.purpleAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.insert_drive_file_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.media.originalFilename,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.media.isEncrypted) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.lock_rounded, color: Colors.pinkAccent, size: 12),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "${widget.media.mimeType.split('/').last.toUpperCase()} • ${widget.media.formattedFileSize}",
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _openDocument(context),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Open / Download",
                          style: TextStyle(
                            color: Colors.pinkAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.open_in_new_rounded, color: Colors.pinkAccent, size: 14),
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
  }
}

class AuthenticatedImage extends StatefulWidget {
  final String url;
  final String? fallbackUrl;
  final String token;
  final BoxFit fit;
  final MediaItem? media;

  const AuthenticatedImage({
    super.key,
    required this.url,
    this.fallbackUrl,
    required this.token,
    this.fit = BoxFit.cover,
    this.media,
  });

  @override
  State<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends State<AuthenticatedImage> {
  Uint8List? _bytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.media?.id != widget.media?.id) {
      _loadImage();
    }
  }

  @override
  void dispose() {
    if (widget.media?.isViewOnce == true && _bytes != null) {
      try {
        _bytes!.fillRange(0, _bytes!.length, 0);
      } catch (_) {}
      _bytes = null;
    }
    super.dispose();
  }

  Future<void> _loadImage() async {
    final effectiveToken = widget.token.isNotEmpty ? widget.token : (await Session.getToken() ?? '');
    var data = await ApiService.fetchAuthenticatedBytes(widget.url, effectiveToken);
    if (data == null && widget.fallbackUrl != null) {
      data = await ApiService.fetchAuthenticatedBytes(widget.fallbackUrl!, effectiveToken);
    }

    if (data != null && widget.media != null && widget.media!.isEncrypted &&
        widget.media!.encryptedMediaKey != null && widget.media!.encryptionNonce != null) {
      try {
        final media = widget.media!;
        final myId = await Session.getUserId();
        final partnerId = (media.senderId == myId) ? media.receiverId : media.senderId;
        final partnerPubKey = await E2EEService.getPartnerPublicKey(partnerId, token: effectiveToken);

        if (partnerPubKey != null && partnerPubKey.isNotEmpty) {
          final decrypted = await E2EEService.decryptMediaBytes(
            encryptedFileBytes: data,
            encryptedMediaKeyBundleJson: media.encryptedMediaKey!,
            nonceBase64: media.encryptionNonce!,
            remotePublicKeyBase64: partnerPubKey,
          );
          if (decrypted != null) {
            data = decrypted;
          }
        }
      } catch (e) {
        debugPrint("E2EE IMAGE DECRYPT IN BUBBLE ERROR: $e");
      }
    }

    if (mounted) {
      setState(() {
        _bytes = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.white10,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.pinkAccent, strokeWidth: 2),
        ),
      );
    }

    if (_bytes == null) {
      return Container(
        color: Colors.white10,
        child: const Center(
          child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 32),
        ),
      );
    }

    return Image.memory(_bytes!, fit: widget.fit);
  }
}
