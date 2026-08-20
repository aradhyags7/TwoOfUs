import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/media.dart';
import '../services/api_service.dart';
import '../services/e2ee_service.dart';
import '../utils/session.dart';

class VideoPlayerDialog extends StatefulWidget {
  final String videoUrl;
  final String token;
  final String? title;
  final MediaItem? media;

  const VideoPlayerDialog({
    super.key,
    required this.videoUrl,
    required this.token,
    this.title,
    this.media,
  });

  @override
  State<VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<VideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = "";
  File? _localVideoFile;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    try {
      final effectiveToken = widget.token.isNotEmpty ? widget.token : (await Session.getToken() ?? '');
      final rawBytes = await ApiService.fetchAuthenticatedBytes(widget.videoUrl, effectiveToken);
      if (rawBytes == null) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = "Failed to download video with authentication";
          });
        }
        return;
      }

      Uint8List videoBytesToPlay = rawBytes;
      if (widget.media != null && widget.media!.isEncrypted &&
          widget.media!.encryptedMediaKey != null && widget.media!.encryptionNonce != null) {
        final media = widget.media!;
        final myId = await Session.getUserId();
        final partnerId = (media.senderId == myId) ? media.receiverId : media.senderId;
        final partnerPubKey = await E2EEService.getPartnerPublicKey(partnerId, token: effectiveToken);

        if (partnerPubKey != null && partnerPubKey.isNotEmpty) {
          final decrypted = await E2EEService.decryptMediaBytes(
            encryptedFileBytes: rawBytes,
            encryptedMediaKeyBundleJson: media.encryptedMediaKey!,
            nonceBase64: media.encryptionNonce!,
            remotePublicKeyBase64: partnerPubKey,
          );
          if (decrypted != null) {
            videoBytesToPlay = decrypted;
          }
        }
      }

      final tempDir = Directory.systemTemp;
      final file = File("${tempDir.path}/video_cache_${DateTime.now().millisecondsSinceEpoch}.mp4");
      await file.writeAsBytes(videoBytesToPlay);

      if (await file.exists()) {
        _localVideoFile = file;
        _controller = VideoPlayerController.file(file);
        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          _controller!.play();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    if (_localVideoFile != null && _localVideoFile!.existsSync()) {
      try {
        _localVideoFile!.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.title ?? "Video Player",
                style: const TextStyle(color: Colors.white, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.media != null && widget.media!.isEncrypted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.pinkAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, color: Colors.pinkAccent, size: 12),
                    SizedBox(width: 4),
                    Text(
                      "E2EE",
                      style: TextStyle(color: Colors.pinkAccent, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: Center(
        child: _hasError
            ? Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      "Failed to play video",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : !_isInitialized
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.pinkAccent),
                      SizedBox(height: 16),
                      Text("Downloading & decrypting video...", style: TextStyle(color: Colors.grey)),
                    ],
                  )
                : AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(_controller!),
                        _ControlsOverlay(controller: _controller!),
                        VideoProgressIndicator(
                          _controller!,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.pinkAccent,
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _ControlsOverlay extends StatefulWidget {
  final VideoPlayerController controller;

  const _ControlsOverlay({required this.controller});

  @override
  State<_ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          widget.controller.value.isPlaying
              ? widget.controller.pause()
              : widget.controller.play();
        });
      },
      child: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            reverseDuration: const Duration(milliseconds: 200),
            child: widget.controller.value.isPlaying
                ? const SizedBox.shrink()
                : Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 72.0,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
