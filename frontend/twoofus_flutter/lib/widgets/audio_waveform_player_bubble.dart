import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media.dart';
import '../services/api_service.dart';
import '../services/e2ee_service.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';

class AudioWaveformPlayerBubble extends StatefulWidget {
  final MediaItem media;
  final String token;
  final bool isMe;

  const AudioWaveformPlayerBubble({
    super.key,
    required this.media,
    required this.token,
    required this.isMe,
  });

  @override
  State<AudioWaveformPlayerBubble> createState() => _AudioWaveformPlayerBubbleState();
}

class _AudioWaveformPlayerBubbleState extends State<AudioWaveformPlayerBubble> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = false;
  double _playbackRate = 1.0;
  String? _localDecryptedPath;
  late final List<double> _waveformSamples;

  @override
  void initState() {
    super.initState();
    // Deterministic pseudo-random waveform based on media id and file size
    _waveformSamples = _generateWaveformSamples(widget.media.id, widget.media.fileSize);

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });

    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playerState = PlayerState.completed;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  List<double> _generateWaveformSamples(int seed, int size) {
    final rand = Random(seed ^ size);
    return List.generate(32, (index) {
      final base = 0.25 + 0.75 * rand.nextDouble();
      // Wave shape tapering at edges
      final envelope = sin((index + 1) / 33.0 * pi);
      return (base * envelope).clamp(0.15, 1.0);
    });
  }

  Future<String?> _getDecryptedFilePath() async {
    if (_localDecryptedPath != null && File(_localDecryptedPath!).existsSync()) {
      return _localDecryptedPath;
    }

    final tempDir = Directory.systemTemp;
    final cachedPath = "${tempDir.path}/voice_${widget.media.id}.m4a";
    final cachedFile = File(cachedPath);
    if (cachedFile.existsSync() && cachedFile.lengthSync() > 0) {
      _localDecryptedPath = cachedPath;
      return cachedPath;
    }

    final fileUrl = ApiService.getMediaFileUrl(widget.media.id);
    final effectiveToken = widget.token.isNotEmpty ? widget.token : (await Session.getToken() ?? '');
    final rawBytes = await ApiService.fetchAuthenticatedBytes(fileUrl, effectiveToken);
    if (rawBytes == null) return null;

    Uint8List fileBytesToPlay = rawBytes;
    if (widget.media.isEncrypted &&
        widget.media.encryptedMediaKey != null &&
        widget.media.encryptionNonce != null) {
      final myId = await Session.getUserId();
      final cachedPartnerId = await Session.getCachedPartnerId();
      final partnerId = (myId != null && widget.media.senderId == myId)
          ? widget.media.receiverId
          : ((cachedPartnerId != null && widget.media.receiverId == cachedPartnerId)
              ? cachedPartnerId
              : widget.media.senderId);

      final partnerPubKey = await E2EEService.getPartnerPublicKey(partnerId, token: effectiveToken);
      if (partnerPubKey != null && partnerPubKey.isNotEmpty) {
        final decrypted = await E2EEService.decryptMediaBytes(
          encryptedFileBytes: rawBytes,
          encryptedMediaKeyBundleJson: widget.media.encryptedMediaKey!,
          nonceBase64: widget.media.encryptionNonce!,
          remotePublicKeyBase64: partnerPubKey,
        );
        if (decrypted != null) {
          fileBytesToPlay = decrypted;
        }
      }
    }

    await cachedFile.writeAsBytes(fileBytesToPlay);
    _localDecryptedPath = cachedPath;
    return cachedPath;
  }

  Future<void> _togglePlayPause() async {
    HapticFeedback.selectionClick();
    if (_playerState == PlayerState.playing) {
      await _player.pause();
      return;
    }

    if (_playerState == PlayerState.paused) {
      await _player.resume();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final path = await _getDecryptedFilePath();
      if (path != null && File(path).existsSync()) {
        await _player.setPlaybackRate(_playbackRate);
        await _player.play(DeviceFileSource(path));
      }
    } catch (e) {
      if (kDebugMode) print("[AudioWaveformPlayerBubble] playback error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePlaybackSpeed() async {
    HapticFeedback.lightImpact();
    double nextRate = 1.0;
    if (_playbackRate == 1.0) {
      nextRate = 1.5;
    } else if (_playbackRate == 1.5) {
      nextRate = 2.0;
    } else {
      nextRate = 1.0;
    }

    setState(() => _playbackRate = nextRate);
    await _player.setPlaybackRate(nextRate);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isPlaying = _playerState == PlayerState.playing;
    final accent = theme.isDark ? theme.accentBright : theme.accentFill;

    final totalMillis = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMillis = _position.inMilliseconds.toDouble().clamp(0.0, totalMillis);
    final progress = (currentMillis / totalMillis).clamp(0.0, 1.0);

    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe
            ? (theme.isDark ? theme.accentFill.withValues(alpha: 0.18) : theme.accentFill.withValues(alpha: 0.12))
            : theme.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isMe ? accent.withValues(alpha: 0.25) : theme.border,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Play / Pause / Loading button
              GestureDetector(
                onTap: _isLoading ? null : _togglePlayPause,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: theme.onAccent,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: theme.onAccent,
                            size: 24,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Interactive Waveform with Scrubbing
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        if (_duration.inMilliseconds > 0) {
                          final localX = details.localPosition.dx.clamp(0.0, width);
                          final seekRatio = localX / width;
                          final seekMs = (seekRatio * _duration.inMilliseconds).toInt();
                          _player.seek(Duration(milliseconds: seekMs));
                        }
                      },
                      onTapDown: (details) {
                        if (_duration.inMilliseconds > 0) {
                          final localX = details.localPosition.dx.clamp(0.0, width);
                          final seekRatio = localX / width;
                          final seekMs = (seekRatio * _duration.inMilliseconds).toInt();
                          _player.seek(Duration(milliseconds: seekMs));
                        }
                      },
                      child: SizedBox(
                        height: 36,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(_waveformSamples.length, (index) {
                            final barHeight = 6.0 + (_waveformSamples[index] * 24.0);
                            final barProgress = index / _waveformSamples.length;
                            final isPlayed = barProgress <= progress;

                            return Container(
                              width: 3.2,
                              height: barHeight,
                              decoration: BoxDecoration(
                                color: isPlayed
                                    ? accent
                                    : (widget.isMe
                                        ? accent.withValues(alpha: 0.3)
                                        : theme.textTertiary.withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Playback Speed Toggle Pill (1.0x, 1.5x, 2.0x)
              GestureDetector(
                onTap: _togglePlaybackSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.border, width: 0.8),
                  ),
                  child: Text(
                    "${_playbackRate == 1.0 ? '1' : _playbackRate.toString()}x",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Duration / Elapsed indicator & E2EE voice note tag
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _duration == Duration.zero
                      ? "Voice note"
                      : "${_formatDuration(_position)} / ${_formatDuration(_duration)}",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_rounded, size: 10, color: theme.textTertiary),
                    if (widget.media.isEncrypted) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.lock_rounded, size: 10, color: theme.success),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
