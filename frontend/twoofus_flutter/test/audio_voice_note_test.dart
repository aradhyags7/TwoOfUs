import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoofus_flutter/models/media.dart';
import 'package:twoofus_flutter/widgets/audio_waveform_player_bubble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio Voice Note & Waveform Tests', () {
    test('MediaItem correctly identifies audio file formats and mime types', () {
      final audioItem1 = MediaItem(
        id: 1,
        senderId: 10,
        receiverId: 20,
        storagePath: '/storage/voice_1.m4a',
        storedFilename: 'stored_voice_1.m4a',
        originalFilename: 'voice_1.m4a',
        mediaType: 'audio',
        mimeType: 'audio/m4a',
        fileSize: 48000,
        isViewOnce: false,
        createdAt: DateTime.now(),
      );

      final audioItem2 = MediaItem(
        id: 2,
        senderId: 10,
        receiverId: 20,
        storagePath: '/storage/note.aac',
        storedFilename: 'stored_note.aac',
        originalFilename: 'note.aac',
        mediaType: 'audio',
        mimeType: 'audio/aac',
        fileSize: 32000,
        isViewOnce: false,
        createdAt: DateTime.now(),
      );

      final audioItem3 = MediaItem(
        id: 3,
        senderId: 10,
        receiverId: 20,
        storagePath: '/storage/recording.mp3',
        storedFilename: 'stored_recording.mp3',
        originalFilename: 'recording.mp3',
        mediaType: 'audio',
        mimeType: 'audio/mpeg',
        fileSize: 64000,
        isViewOnce: false,
        createdAt: DateTime.now(),
      );

      final imageItem = MediaItem(
        id: 4,
        senderId: 10,
        receiverId: 20,
        storagePath: '/storage/photo.jpg',
        storedFilename: 'stored_photo.jpg',
        originalFilename: 'photo.jpg',
        mediaType: 'image',
        mimeType: 'image/jpeg',
        fileSize: 102400,
        isViewOnce: false,
        createdAt: DateTime.now(),
      );

      final videoItem = MediaItem(
        id: 5,
        senderId: 10,
        receiverId: 20,
        storagePath: '/storage/video.mp4',
        storedFilename: 'stored_video.mp4',
        originalFilename: 'video.mp4',
        mediaType: 'video',
        mimeType: 'video/mp4',
        fileSize: 1024000,
        isViewOnce: false,
        createdAt: DateTime.now(),
      );

      expect(audioItem1.isAudio, isTrue);
      expect(audioItem1.isImage, isFalse);
      expect(audioItem1.isVideo, isFalse);

      expect(audioItem2.isAudio, isTrue);
      expect(audioItem3.isAudio, isTrue);

      expect(imageItem.isAudio, isFalse);
      expect(imageItem.isImage, isTrue);

      expect(videoItem.isAudio, isFalse);
      expect(videoItem.isVideo, isTrue);
    });

    test('Audio duration formatter computes MM:SS accurately', () {
      String formatDuration(Duration d) {
        final m = d.inMinutes;
        final s = d.inSeconds % 60;
        return '$m:${s.toString().padLeft(2, '0')}';
      }

      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 7)), '0:07');
      expect(formatDuration(const Duration(seconds: 45)), '0:45');
      expect(formatDuration(const Duration(seconds: 60)), '1:00');
      expect(formatDuration(const Duration(seconds: 83)), '1:23');
      expect(formatDuration(const Duration(minutes: 5, seconds: 9)), '5:09');
      expect(formatDuration(const Duration(minutes: 12, seconds: 34)), '12:34');
    });

    testWidgets('AudioWaveformPlayerBubble renders play icon, speed pill, and duration', (tester) async {
      final audioMedia = MediaItem(
        id: 42,
        senderId: 1,
        receiverId: 2,
        storagePath: '/storage/voice_42.m4a',
        storedFilename: 'stored_voice_42.m4a',
        originalFilename: 'voice_42.m4a',
        mediaType: 'audio',
        mimeType: 'audio/m4a',
        fileSize: 24500,
        isViewOnce: false,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AudioWaveformPlayerBubble(
                media: audioMedia,
                token: 'mock-test-token',
                isMe: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify play icon is rendered
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Verify playback speed pill exists with initial 1x
      expect(find.text('1x'), findsOneWidget);

      // Verify initial label shows "Voice note" when duration is 0
      expect(find.text('Voice note'), findsOneWidget);

      // Verify mic icon is displayed
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });
  });
}

