import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoofus_flutter/theme/app_theme.dart';
import 'package:twoofus_flutter/theme/theme_controller.dart';
import 'package:twoofus_flutter/screens/login_screen.dart';
import 'package:twoofus_flutter/models/diary_memory.dart';
import 'package:twoofus_flutter/widgets/timeline_drawer.dart';
import 'package:twoofus_flutter/widgets/design_system/design_system.dart';

Widget wrapWithTheme({
  required Widget child,
  required AppTheme theme,
  double width = 390.0,
  double height = 844.0,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeController.buildThemeData(theme),
    home: Scaffold(
      backgroundColor: theme.bg,
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Visual Golden Tests', () {
    testWidgets('Golden Test - Login Screen', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final darkTheme = AppTheme.dark(AppAccent.indigo);

      await tester.pumpWidget(
        wrapWithTheme(
          child: const LoginScreen(),
          theme: darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(LoginScreen),
        matchesGoldenFile('goldens/login_screen.png'),
      );
    });

    testWidgets('Golden Test - Chat Screen Dark', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final darkTheme = AppTheme.dark(AppAccent.indigo);

      final chatView = Scaffold(
        backgroundColor: darkTheme.bg,
        appBar: AppBar(
          backgroundColor: darkTheme.surface,
          title: Row(
            children: [
              const AppAvatar(name: 'Sarah Connor', size: 38, isOnline: true),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sarah Connor', style: TextStyle(color: darkTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Online', style: TextStyle(color: AppColors.darkSuccess, fontSize: 12)),
                ],
              ),
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
                    icon: Icons.lock_outline_rounded,
                    text: 'Messages are end-to-end encrypted',
                    time: '10:00',
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: darkTheme.bubblePartner,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                          bottomLeft: Radius.circular(4),
                        ),
                        border: Border.all(color: darkTheme.border),
                      ),
                      child: Text(
                        'Hey, are you ready for the meeting?',
                        style: TextStyle(color: darkTheme.textPrimary, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: darkTheme.bubbleSelf,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: Text(
                        'Yes, joining right now!',
                        style: TextStyle(color: darkTheme.onAccent, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              color: darkTheme.surface,
              child: Row(
                children: [
                  const Expanded(
                    child: AppTextField(hintText: 'Type a message...'),
                  ),
                  const SizedBox(width: 8),
                  AppButton(text: 'Send', onPressed: () {}),
                ],
              ),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        wrapWithTheme(
          child: chatView,
          theme: darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/chat_dark.png'),
      );
    });

    testWidgets('Golden Test - Chat Screen Light', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final lightTheme = AppTheme.light(AppAccent.indigo);

      final chatView = Scaffold(
        backgroundColor: lightTheme.bg,
        appBar: AppBar(
          backgroundColor: lightTheme.surface,
          title: Row(
            children: [
              const AppAvatar(name: 'Sarah Connor', size: 38, isOnline: true),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sarah Connor', style: TextStyle(color: lightTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Online', style: TextStyle(color: AppColors.lightSuccess, fontSize: 12)),
                ],
              ),
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
                    icon: Icons.lock_outline_rounded,
                    text: 'Messages are end-to-end encrypted',
                    time: '10:00',
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: lightTheme.bubblePartner,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                          bottomLeft: Radius.circular(4),
                        ),
                        border: Border.all(color: lightTheme.border),
                      ),
                      child: Text(
                        'Hey, are you ready for the meeting?',
                        style: TextStyle(color: lightTheme.textPrimary, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: lightTheme.bubbleSelf,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: Text(
                        'Yes, joining right now!',
                        style: TextStyle(color: lightTheme.onAccent, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              color: lightTheme.surface,
              child: Row(
                children: [
                  const Expanded(
                    child: AppTextField(hintText: 'Type a message...'),
                  ),
                  const SizedBox(width: 8),
                  AppButton(text: 'Send', onPressed: () {}),
                ],
              ),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        wrapWithTheme(
          child: chatView,
          theme: lightTheme,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/chat_light.png'),
      );
    });

    testWidgets('Golden Test - Drawer Settings Panel', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final darkTheme = AppTheme.dark(AppAccent.indigo);

      final drawerWidget = Material(
        color: darkTheme.bg,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const AppAvatar(name: 'My Profile', size: 48),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My Profile', style: TextStyle(color: darkTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('@my_username', style: TextStyle(color: darkTheme.textMuted, fontSize: 13)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SectionGroup(
              title: 'Settings',
              children: [
                AppListTile(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: 'Dark • Indigo',
                  onTap: () {},
                ),
                AppListTile(
                  icon: Icons.shield_outlined,
                  title: 'Security',
                  subtitle: 'Passcode & 2FA',
                  onTap: () {},
                ),
                AppListTile(
                  icon: Icons.storage_outlined,
                  title: 'Data & Storage',
                  subtitle: 'Network usage',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        wrapWithTheme(
          child: drawerWidget,
          theme: darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Material).first,
        matchesGoldenFile('goldens/drawer.png'),
      );
    });

    testWidgets('Golden Test - Partner Profile Header & Settings', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final darkTheme = AppTheme.dark(AppAccent.indigo);

      final profileWidget = Material(
        color: darkTheme.bg,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  const AppAvatar(name: 'Sarah Connor', size: 80, isOnline: true),
                  const SizedBox(height: 12),
                  Text('Sarah Connor', style: TextStyle(color: darkTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Online', style: TextStyle(color: AppColors.darkSuccess, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionGroup(
              title: 'About',
              children: [
                AppListTile(
                  icon: Icons.notes_rounded,
                  title: 'Living life one day at a time',
                  subtitle: 'Bio',
                ),
                AppListTile(
                  icon: Icons.email_outlined,
                  title: 'sarah@example.com',
                  subtitle: 'Email',
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionGroup(
              title: 'Settings & Privacy',
              children: [
                AppListTile(
                  icon: Icons.palette_outlined,
                  title: 'Chat Theme & Wallpaper',
                  subtitle: 'Indigo • Dark',
                  onTap: () {},
                ),
                AppListTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Encryption & Safety Code',
                  subtitle: '60-digit verification code',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        wrapWithTheme(
          child: profileWidget,
          theme: darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Material).first,
        matchesGoldenFile('goldens/profile.png'),
      );
    });

    testWidgets('Golden Test - Timeline Drawer', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final darkTheme = AppTheme.dark(AppAccent.indigo);

      final drawerWidget = TimelineDrawer(
        memories: [
          DiaryMemoryItem(
            id: 1,
            senderId: 1,
            receiverId: 2,
            entryDate: '2026-10-10',
            content: 'Our weekend getaway to the mountains!',
            moodEmoji: '✈️',
          ),
          DiaryMemoryItem(
            id: 2,
            senderId: 2,
            receiverId: 1,
            entryDate: '2026-10-09',
            content: 'Coffee and morning walk in the park.',
            moodEmoji: '☕',
          ),
        ],
        selectedDate: DateTime(2026, 10, 10),
        onSelectDate: (_) {},
        onRefresh: () {},
        onClose: () {},
        onSaveMemory: (_, __, ___) async {},
        onDeleteMemory: (_) {},
        partnerName: 'Sarah Connor',
        myId: 1,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          child: drawerWidget,
          theme: darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(TimelineDrawer),
        matchesGoldenFile('goldens/timeline_drawer.png'),
      );
    });
  });
}
