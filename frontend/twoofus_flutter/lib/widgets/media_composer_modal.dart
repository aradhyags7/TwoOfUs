import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import '../services/e2ee_service.dart';
import '../utils/session.dart';
import 'image_crop_editor.dart';
import 'view_once_badge.dart';

class MediaComposerModal extends StatefulWidget {
  final int receiverId;
  final List<File> selectedFiles;
  final String token;
  final String? partnerPubKey;
  final Function(List<int> uploadedMediaIds, String caption) onSendComplete;

  const MediaComposerModal({
    super.key,
    required this.receiverId,
    required this.selectedFiles,
    required this.token,
    this.partnerPubKey,
    required this.onSendComplete,
  });

  @override
  State<MediaComposerModal> createState() => _MediaComposerModalState();
}

class _MediaComposerModalState extends State<MediaComposerModal> {
  final TextEditingController _captionController = TextEditingController();
  late List<File> _files;
  int _currentIndex = 0;
  late PageController _pageController;

  // Video playback controllers per file index
  final Map<int, VideoPlayerController> _videoControllers = {};

  // Video settings per file index
  final Map<int, bool> _videoMuted = {};
  final Map<int, RangeValues> _videoTrim = {};
  bool _showVideoTrimmer = false;

  // View Once (1) Mode
  bool _isViewOnce = false;

  // Upload state
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  bool _hasError = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _files = List.from(widget.selectedFiles);
    _pageController = PageController(initialPage: 0);
    _initVideoForIndex(0);
  }

  @override
  void dispose() {
    _captionController.dispose();
    _pageController.dispose();
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _isVideo(File file) {
    final path = file.path.toLowerCase();
    return path.endsWith('.mp4') || path.endsWith('.mov') || path.endsWith('.mkv') || path.endsWith('.webm') || path.endsWith('.avi');
  }

  Future<void> _initVideoForIndex(int index) async {
    if (index < 0 || index >= _files.length) return;
    final file = _files[index];
    if (!_isVideo(file)) return;

    if (!_videoControllers.containsKey(index)) {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      controller.setLooping(true);
      _videoControllers[index] = controller;
      _videoMuted[index] = false;
      _videoTrim[index] = RangeValues(0.0, controller.value.duration.inSeconds.toDouble());
      if (mounted) setState(() {});
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _showVideoTrimmer = false;
    });
    // Pause previous videos
    _videoControllers.forEach((key, controller) {
      if (key != index && controller.value.isPlaying) {
        controller.pause();
      }
    });
    _initVideoForIndex(index);
  }

  void _removeCurrentFile() {
    HapticFeedback.mediumImpact();
    if (_files.isEmpty) return;

    final removedIndex = _currentIndex;
    _videoControllers[removedIndex]?.dispose();
    _videoControllers.remove(removedIndex);

    setState(() {
      _files.removeAt(removedIndex);
      if (_files.isEmpty) {
        Navigator.pop(context);
        return;
      }
      if (_currentIndex >= _files.length) {
        _currentIndex = _files.length - 1;
      }
    });
    _pageController.jumpToPage(_currentIndex);
    _initVideoForIndex(_currentIndex);
  }

  Future<void> _addMoreMedia() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isNotEmpty) {
      setState(() {
        _files.addAll(picked.map((x) => File(x.path)));
      });
    }
  }

  Future<void> _openCropEditor() async {
    if (_files.isEmpty) return;
    final currentFile = _files[_currentIndex];
    if (_isVideo(currentFile)) return;

    HapticFeedback.selectionClick();
    final editedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageCropEditor(imageFile: currentFile),
      ),
    );

    if (editedFile != null && mounted) {
      setState(() {
        _files[_currentIndex] = editedFile;
      });
    }
  }

  void _toggleVideoSound() {
    HapticFeedback.selectionClick();
    final isMuted = _videoMuted[_currentIndex] ?? false;
    final newMuted = !isMuted;
    final controller = _videoControllers[_currentIndex];
    controller?.setVolume(newMuted ? 0.0 : 1.0);

    setState(() {
      _videoMuted[_currentIndex] = newMuted;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newMuted ? "🔇 Audio muted for video" : "🔊 Audio enabled for video"),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleViewOnce() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isViewOnce = !_isViewOnce;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isViewOnce
            ? "1️⃣ View Once enabled. Media can only be opened once."
            : "Media will be kept permanently in chat."),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startUpload() async {
    if (_files.isEmpty) return;

    setState(() {
      _isUploading = true;
      _hasError = false;
      _errorMessage = "";
      _uploadProgress = 0.15;
    });

    List<int> allMediaIds = [];
    final tempEncFiles = <File>[];
    final effectiveToken = widget.token.isNotEmpty ? widget.token : (await Session.getToken() ?? '');

    try {
      if (widget.partnerPubKey != null && widget.partnerPubKey!.isNotEmpty) {
        // E2EE Media Encryption Mode
        for (int i = 0; i < _files.length; i++) {
          final originalFile = _files[i];
          final encPayload = await E2EEService.encryptFile(originalFile, widget.partnerPubKey!);

          if (encPayload != null) {
            final tempDir = Directory.systemTemp;
            final origName = originalFile.path.split(Platform.pathSeparator).last;
            final encTempPath = "${tempDir.path}/enc_${DateTime.now().millisecondsSinceEpoch}_$origName";
            final encTempFile = File(encTempPath);
            await encTempFile.writeAsBytes(encPayload.encryptedBytes);
            tempEncFiles.add(encTempFile);

            final results = await ApiService.uploadMediaFiles(
              widget.receiverId,
              [encTempFile],
              effectiveToken,
              isEncrypted: true,
              isViewOnce: _isViewOnce,
              encryptedMediaKey: encPayload.encryptedMediaKey,
              encryptionNonce: encPayload.nonce,
              onProgress: (p) => setState(() => _uploadProgress = ((i + p) / _files.length).clamp(0.0, 1.0)),
            );

            if (results != null && results.isNotEmpty) {
              allMediaIds.addAll(results.map<int>((e) => e['media_id'] as int));
            }
          } else {
            // Fallback for single file if encryption had an issue
            final results = await ApiService.uploadMediaFiles(
              widget.receiverId,
              [originalFile],
              effectiveToken,
              isViewOnce: _isViewOnce,
              onProgress: (p) => setState(() => _uploadProgress = ((i + p) / _files.length).clamp(0.0, 1.0)),
            );
            if (results != null && results.isNotEmpty) {
              allMediaIds.addAll(results.map<int>((e) => e['media_id'] as int));
            }
          }
        }
      } else {
        // Standard Upload Mode
        final results = await ApiService.uploadMediaFiles(
          widget.receiverId,
          _files,
          effectiveToken,
          isViewOnce: _isViewOnce,
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
        if (results != null && results.isNotEmpty) {
          allMediaIds.addAll(results.map<int>((e) => e['media_id'] as int));
        }
      }

      // Cleanup temp encrypted files
      for (var f in tempEncFiles) {
        if (f.existsSync()) {
          try { f.deleteSync(); } catch (_) {}
        }
      }

      if (allMediaIds.isNotEmpty) {
        setState(() => _uploadProgress = 1.0);
        widget.onSendComplete(allMediaIds, _captionController.text.trim());
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          setState(() {
            _isUploading = false;
            _hasError = true;
            _errorMessage = "Upload failed. Please check connection and retry.";
          });
        }
      }
    } catch (e) {
      for (var f in tempEncFiles) {
        if (f.existsSync()) {
          try { f.deleteSync(); } catch (_) {}
        }
      }
      if (mounted) {
        setState(() {
          _isUploading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF0A0A0E);
    const rose = Color(0xFFFF2D75);
    const violet = Color(0xFF9B51E0);

    if (_files.isEmpty) return const SizedBox.shrink();
    final currentFile = _files[_currentIndex];
    final isCurrentVideo = _isVideo(currentFile);
    final isMuted = _videoMuted[_currentIndex] ?? false;

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top Studio Action Bar
                _buildTopActionBar(rose, violet, isCurrentVideo, isMuted),

                // Main Interactive Viewport
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _files.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      if (_isVideo(file)) {
                        return _buildVideoPreview(index);
                      } else {
                        return InteractiveViewer(
                          minScale: 0.8,
                          maxScale: 3.5,
                          child: Center(
                            child: Image.file(
                              file,
                              fit: BoxFit.contain,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),

                // Video Trimmer Controls (if visible)
                if (isCurrentVideo && _showVideoTrimmer)
                  _buildVideoTrimmerBar(rose),

                // Bottom Thumbnail Carousel Strip
                _buildThumbnailStrip(rose),

                // Floating Caption Bar & View Once Toggle
                _buildCaptionBar(rose, violet),
              ],
            ),

            // Upload Progress & Spinner Overlay
            if (_isUploading)
              Container(
                color: Colors.black.withValues(alpha: 0.75),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: CircularProgressIndicator(
                              value: _uploadProgress > 0 ? _uploadProgress : null,
                              color: rose,
                              strokeWidth: 4,
                            ),
                          ),
                          Icon(Icons.lock_rounded, color: rose, size: 24),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Encrypting & Sending ${(_uploadProgress * 100).toInt()}%",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "End-to-End Encrypted Transfer",
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionBar(Color rose, Color violet, bool isCurrentVideo, bool isMuted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
            onPressed: _isUploading ? null : () => Navigator.pop(context),
          ),
          if (widget.partnerPubKey != null && widget.partnerPubKey!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: rose.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: rose.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, color: Colors.pinkAccent, size: 12),
                  SizedBox(width: 4),
                  Text(
                    "E2EE",
                    style: TextStyle(color: Colors.pinkAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          const Spacer(),
          if (!isCurrentVideo) ...[
            // Photo Crop & Rotate Tool
            IconButton(
              tooltip: "Crop & Rotate",
              icon: const Icon(Icons.crop_rotate_rounded, color: Colors.white, size: 24),
              onPressed: _isUploading ? null : _openCropEditor,
            ),
          ] else ...[
            // Video Sound Mute Toggle
            IconButton(
              tooltip: isMuted ? "Unmute Audio" : "Mute Audio",
              icon: Icon(
                isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: isMuted ? Colors.redAccent : Colors.white,
                size: 24,
              ),
              onPressed: _isUploading ? null : _toggleVideoSound,
            ),
            // Video Trim Range Tool
            IconButton(
              tooltip: "Trim Video",
              icon: Icon(
                Icons.content_cut_rounded,
                color: _showVideoTrimmer ? rose : Colors.white,
                size: 22,
              ),
              onPressed: _isUploading ? null : () => setState(() => _showVideoTrimmer = !_showVideoTrimmer),
            ),
          ],
          // Delete Current Item
          IconButton(
            tooltip: "Remove Item",
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 24),
            onPressed: _isUploading ? null : _removeCurrentFile,
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview(int index) {
    final controller = _videoControllers[index];
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            GestureDetector(
              onTap: () {
                setState(() {
                  controller.value.isPlaying ? controller.pause() : controller.play();
                });
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: controller.value.isPlaying ? 0.0 : 1.0,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoTrimmerBar(Color rose) {
    final controller = _videoControllers[_currentIndex];
    final totalDuration = controller?.value.duration.inSeconds.toDouble() ?? 30.0;
    final currentRange = _videoTrim[_currentIndex] ?? RangeValues(0.0, totalDuration);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black87,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Trim Duration", style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text(
                "${currentRange.start.toInt()}s - ${currentRange.end.toInt()}s (${(currentRange.end - currentRange.start).toInt()}s)",
                style: TextStyle(color: rose, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          RangeSlider(
            values: currentRange,
            min: 0.0,
            max: totalDuration > 0 ? totalDuration : 1.0,
            activeColor: rose,
            inactiveColor: Colors.white24,
            onChanged: (newRange) {
              setState(() {
                _videoTrim[_currentIndex] = newRange;
              });
              controller?.seekTo(Duration(seconds: newRange.start.toInt()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailStrip(Color rose) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.black.withValues(alpha: 0.4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _files.length + 1,
        itemBuilder: (context, index) {
          if (index == _files.length) {
            // Add More Button
            return GestureDetector(
              onTap: _isUploading ? null : _addMoreMedia,
              child: Container(
                width: 56,
                height: 56,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
              ),
            );
          }

          final file = _files[index];
          final isSelected = index == _currentIndex;
          final isVideo = _isVideo(file);

          return GestureDetector(
            onTap: () {
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 56,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? rose : Colors.transparent,
                  width: isSelected ? 2.5 : 1.0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!isVideo)
                      Image.file(file, fit: BoxFit.cover)
                    else
                      Container(
                        color: Colors.purple.withValues(alpha: 0.3),
                        child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 24),
                      ),
                    if (isVideo)
                      const Positioned(
                        bottom: 2,
                        right: 2,
                        child: Icon(Icons.play_circle_filled_rounded, color: Colors.white, size: 14),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaptionBar(Color rose, Color violet) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: BoxDecoration(
        color: const Color(0xFF14141E),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Error Banner if upload failed
          if (_hasError) ...[
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage.isNotEmpty ? _errorMessage : "Upload failed. Please retry.",
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Input Row
          Row(
            children: [
              // View Once (1) Button
              ViewOnceBadge(
                isActive: _isViewOnce,
                size: 42,
                onTap: _isUploading ? null : _toggleViewOnce,
              ),
              const SizedBox(width: 10),

              // Caption Text Field
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _captionController,
                    enabled: !_isUploading,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _isViewOnce ? "View once message..." : "Add a caption...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Gradient Send Button FAB
              GestureDetector(
                onTap: _isUploading ? null : _startUpload,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [rose, violet]),
                    boxShadow: [
                      BoxShadow(
                        color: rose.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
