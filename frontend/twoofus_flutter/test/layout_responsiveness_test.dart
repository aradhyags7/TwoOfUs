import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoofus_flutter/theme/app_theme.dart';
import 'package:twoofus_flutter/theme/theme_controller.dart';
import 'package:twoofus_flutter/screens/login_screen.dart';
import 'package:twoofus_flutter/screens/partner_profile_screen.dart';
import 'package:twoofus_flutter/screens/theme_selection_screen.dart';
import 'package:twoofus_flutter/widgets/design_system/design_system.dart';
import 'package:twoofus_flutter/widgets/timeline_drawer.dart';
import 'package:twoofus_flutter/models/diary_memory.dart';
import 'package:twoofus_flutter/widgets/chat_media_bubble.dart';
import 'package:twoofus_flutter/models/media.dart';

Widget createTestApp({
  required Widget child,
  required double width,
  required double textScale,
  AppTheme? theme,
}) {
  final activeTheme = theme ?? AppTheme.dark(AppAccent.indigo);
  return MaterialApp(
    theme: ThemeController.buildThemeData(activeTheme),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 844),
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(top: 44, bottom: 34),
      ),
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widths = [320.0, 360.0, 412.0, 600.0];
  const textScales = [1.0, 1.3];

  group('Layout Responsiveness & Zero Overflow Tests', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('LoginScreen renders at width $width textScale $textScale with zero overflow',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            createTestApp(
              child: const LoginScreen(),
              width: width,
              textScale: textScale,
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(LoginScreen), findsOneWidget);
        });

        testWidgets('ThemeSelectionScreen renders at width $width textScale $textScale with zero overflow',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            createTestApp(
              child: const ThemeSelectionScreen(),
              width: width,
              textScale: textScale,
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(ThemeSelectionScreen), findsOneWidget);
        });

        testWidgets('PartnerProfileScreen renders at width $width textScale $textScale with zero overflow',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            createTestApp(
              child: const PartnerProfileScreen(
                partnerId: 42,
                partnerName: 'Alex River',
                isOnline: true,
              ),
              width: width,
              textScale: textScale,
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byType(PartnerProfileScreen), findsOneWidget);
        });

        testWidgets('TimelineDrawer renders at width $width textScale $textScale with zero overflow',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final sampleMemories = [
            DiaryMemoryItem(
              id: 1,
              senderId: 1,
              receiverId: 2,
              entryDate: '2026-10-11',
              content: 'A wonderful shared memory from our trip to the coast!',
              moodEmoji: '✨',
              imageUrl: null,
            ),
            DiaryMemoryItem(
              id: 2,
              senderId: 2,
              receiverId: 1,
              entryDate: '2026-10-10',
              content: 'Evening planning session for TwoOfUs application.',
              moodEmoji: '☕',
              imageUrl: null,
            ),
          ];

          await tester.pumpWidget(
            createTestApp(
              child: TimelineDrawer(
                memories: sampleMemories,
                isLoading: false,
                onSelectDate: (_) {},
                onRefresh: () {},
                onClose: () {},
                onSaveMemory: (content, mood, photo) async {},
                onDeleteMemory: (_) {},
                partnerName: 'Alex River',
                myId: 1,
              ),
              width: width,
              textScale: textScale,
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(TimelineDrawer), findsOneWidget);
        });

        testWidgets('Chat Messages & Bubble Layout renders at width $width textScale $textScale with zero overflow',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final docMedia = MediaItem(
            id: 1,
            senderId: 1,
            receiverId: 2,
            originalFilename: 'Project_Specification.pdf',
            storedFilename: 'spec_uuid.pdf',
            mediaType: 'file',
            mimeType: 'application/pdf',
            fileSize: 1024 * 345,
            storagePath: 'media/spec_uuid.pdf',
            isEncrypted: true,
          );

          final voMedia = MediaItem(
            id: 2,
            senderId: 2,
            receiverId: 1,
            originalFilename: 'secret_snapshot.jpg',
            storedFilename: 'snap_uuid.jpg',
            mediaType: 'image',
            mimeType: 'image/jpeg',
            fileSize: 1024 * 850,
            storagePath: 'media/snap_uuid.jpg',
            isEncrypted: true,
            isViewOnce: true,
          );

          final videoMedia = MediaItem(
            id: 3,
            senderId: 1,
            receiverId: 2,
            originalFilename: 'anniversary_video.mp4',
            storedFilename: 'vid_uuid.mp4',
            mediaType: 'video',
            mimeType: 'video/mp4',
            fileSize: 1024 * 1024 * 4,
            storagePath: 'media/vid_uuid.mp4',
            isEncrypted: true,
          );

          final maxBubbleWidth = width * 0.78;

          final chatPreview = Scaffold(
            appBar: AppBar(
              title: Row(
                children: const [
                  AppAvatar(name: 'Alex River', size: 36, isOnline: true),
                  SizedBox(width: 10),
                  Text('Alex River', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            body: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const SystemEventRow(
                        icon: Icons.call_rounded,
                        text: 'Voice Call Ended • 12m 45s',
                        time: '12:45',
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurface,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                              bottomLeft: Radius.circular(4),
                            ),
                            border: Border.all(color: AppColors.darkBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ChatMediaBubble(
                                media: voMedia,
                                token: 'test-token',
                                isMe: false,
                              ),
                              const SizedBox(height: 4),
                              const Text('Hey! Sent you a confidential snapshot and documents.'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: const BoxDecoration(
                            color: Color(0xFF4F46E5),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ChatMediaBubble(
                                media: docMedia,
                                token: 'test-token',
                                isMe: true,
                              ),
                              const SizedBox(height: 6),
                              ChatMediaBubble(
                                media: videoMedia,
                                token: 'test-token',
                                isMe: true,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Received! Reviewing the project specifications now.',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.add_rounded), onPressed: () {}),
                      const Expanded(
                        child: AppTextField(hintText: 'Type a message...'),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        text: 'Send',
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          await tester.pumpWidget(
            createTestApp(
              child: chatPreview,
              width: width,
              textScale: textScale,
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byType(ChatMediaBubble), findsNWidgets(3));
        });
      }
    }
  });
}
