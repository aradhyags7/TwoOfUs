import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoofus_flutter/main.dart';
import 'package:twoofus_flutter/services/call_service.dart';
import 'package:twoofus_flutter/services/security_service.dart';

void main() {
  testWidgets('App root initializes smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TwoOfUsApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TwoOfUsApp), findsOneWidget);

    CallService.stopIncomingCallWatcher();
    SecurityService.cancelInactivityTimer();

    // Replace with empty widget to trigger dispose on TwoOfUsApp & SplashScreen
    await tester.pumpWidget(const SizedBox());
    // Drain any remaining delayed timers
    await tester.pump(const Duration(seconds: 2));
  });
}
