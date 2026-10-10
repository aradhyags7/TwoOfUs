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
import '../utils/app_feedback.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

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
    AppFeedback.showInfo(context, 'Downloading ${widget.media.originalFilename}...');

    try {
      final effectiveToken = widget.token.isNotEmpty ? widget.token : (await Session.getToken() ?? '');
      final rawBytes = await ApiService.fetchAuthenticatedBytes(fileUrl, effectiveToken);
      if (rawBytes == null) {
        if (context.mounted) {
          AppFeedback.showError(context, 'Failed to download document');
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
        AppFeedback.showError(context, 'Error opening file: $e');
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
    final theme = context.appTheme;

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
                ? theme.surfaceRaised.withOpacity(0.5)
                : theme.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isConsumed ? theme.border : theme.focusRing.withOpacity(0.6),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ViewOnceBadge(
                isActive: !isConsumed,
                isOpened: isConsumed,
                size: 32,
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
                          fontFamily: 'Inter',
                          color: isConsumed ? theme.textTertiary : theme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.media.isEncrypted) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.lock_rounded, color: theme.textSecondary, size: 12),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isConsumed ? "Opened • Expired" : "Confidential • Tap to reveal",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: isConsumed ? theme.textTertiary : theme.textSecondary,
                      fontSize: 11,
                      fontWeight: isConsumed ? FontWeight.normal : FontWeight.w500,
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
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.border, width: 1),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
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
                      color: theme.surface.withOpacity(0.85),
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.borderSubtle, width: 1),
                    ),
                    child: Icon(Icons.lock_rounded, color: theme.textSecondary, size: 12),
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
          width: 240,
          height: 150,
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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.surface.withOpacity(0.9),
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.border, width: 1),
                    ),
                    child: Icon(Icons.play_arrow_rounded, color: theme.textPrimary, size: 30),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      widget.media.originalFilename,
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
                  const SizedBox(height: 2),
                  Text(
                    widget.media.formattedFileSize,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: theme.textTertiary,
                      fontSize: 10,
                    ),
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
                      color: theme.surface.withOpacity(0.85),
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.borderSubtle, width: 1),
                    ),
                    child: Icon(Icons.lock_rounded, color: theme.textSecondary, size: 12),
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
          color: theme.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.borderSubtle, width: 1),
              ),
              child: Icon(Icons.insert_drive_file_outlined, color: theme.textSecondary, size: 24),
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
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: theme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.media.isEncrypted) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.lock_rounded, color: theme.textSecondary, size: 12),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "${widget.media.mimeType.split('/').last.toUpperCase()} • ${widget.media.formattedFileSize}",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: theme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _openDocument(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Open / Download",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: theme.isDark ? theme.accentBright : theme.accentFill,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.open_in_new_rounded,
                          color: theme.isDark ? theme.accentBright : theme.accentFill,
                          size: 14,
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
  bool _hasError = false;

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

    if (data != null && widget.media != null && widget.media!.isEncrypted) {
      if (widget.media!.encryptedMediaKey != null && widget.media!.encryptionNonce != null) {
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
            } else {
              // Decryption failure - do not render raw ciphertext
              data = null;
            }
          } else {
            // Partner public key unavailable
            data = null;
          }
        } catch (e) {
          debugPrint("E2EE IMAGE DECRYPT IN BUBBLE ERROR: $e");
          data = null;
        }
      } else {
        data = null;
      }
    }

    if (mounted) {
      setState(() {
        _bytes = data;
        _isLoading = false;
        _hasError = (data == null);
      });
    }
  }

  Widget _buildLoadingSkeleton(AppTheme theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.isDark ? theme.accentBright : theme.accentFill,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(AppTheme theme) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isLoading = true;
          _hasError = false;
        });
        _loadImage();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.border, width: 1),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.refresh_rounded,
                color: theme.textSecondary,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                "Couldn't load",
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: theme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Tap to retry",
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: theme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;

    if (_isLoading) {
      return _buildLoadingSkeleton(theme);
    }

    if (_hasError || _bytes == null) {
      return _buildErrorState(theme);
    }

    return Image.memory(
      _bytes!,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorState(theme);
      },
    );
  }
}
