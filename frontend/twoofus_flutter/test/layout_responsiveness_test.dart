import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoofus_flutter/theme/app_theme.dart';
import 'package:twoofus_flutter/theme/theme_controller.dart';
import 'package:twoofus_flutter/screens/login_screen.dart';
import 'package:twoofus_flutter/screens/partner_profile_screen.dart';
import 'package:twoofus_flutter/screens/theme_selection_screen.dart';
import 'package:twoofus_flutter/widgets/design_system/design_system.dart';

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

        testWidgets('Drawer Settings Panel renders at width $width textScale $textScale with zero overflow',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final drawerWidget = Material(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    const AppAvatar(name: 'My Profile', size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('My Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('Online', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionGroup(
                  title: 'Preferences',
                  children: [
                    AppListTile(
                      icon: Icons.palette_outlined,
                      title: 'Appearance',
                      subtitle: 'Dark • Indigo',
                      onTap: () {},
                    ),
                    AppListTile(
                      icon: Icons.security_rounded,
                      title: 'Security',
                      subtitle: 'Passcode & 2FA',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          );

          await tester.pumpWidget(
            createTestApp(
              child: drawerWidget,
              width: width,
              textScale: textScale,
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });

        testWidgets('Chat Messages & Bubble Layout renders at width $width textScale $textScale with zero overflow',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final chatPreview = Scaffold(
            appBar: AppBar(
              title: Row(
                children: const [
                  AppAvatar(name: 'Partner', size: 36, isOnline: true),
                  SizedBox(width: 10),
                  Text('Partner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                          constraints: BoxConstraints(maxWidth: width * 0.78),
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
                          child: const Text('Hey! How is everything going today with the project?'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: width * 0.78),
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
                          child: const Text(
                            'All going great! Zero layout overflows measured.',
                            style: TextStyle(color: Colors.white),
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
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
