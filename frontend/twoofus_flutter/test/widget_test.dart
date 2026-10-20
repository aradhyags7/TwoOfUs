import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoofus_flutter/main.dart';
import 'package:twoofus_flutter/services/call_service.dart';
import 'package:twoofus_flutter/services/fcm_client_service.dart';
import 'package:twoofus_flutter/services/security_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'prompted_full_screen_intent': true});
  });
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

  test('FcmClientService.initialize handles unconfigured Firebase safely without throwing', () async {
    // Assert initialize handles missing Firebase configuration gracefully
    await expectLater(FcmClientService.initialize(), completes);
  });

  test('initFirebaseAndFcm catches and survives failing Firebase and FCM initialization', () async {
    await expectLater(
      initFirebaseAndFcm(
        firebaseInit: () async {
          throw Exception('Simulated Firebase Core initialization exception');
        },
        fcmInit: () async {
          throw Exception('Simulated Firebase Messaging initialization exception');
        },
      ),
      completes,
    );
  });

  testWidgets('App boots normally even when Firebase/FCM init fails or is unconfigured', (WidgetTester tester) async {
    // Simulate boot sequence after init failure
    await initFirebaseAndFcm(
      firebaseInit: () async => throw Exception('Firebase init failure'),
      fcmInit: () async => throw Exception('FCM init failure'),
    );

    await tester.pumpWidget(const TwoOfUsApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TwoOfUsApp), findsOneWidget);

    CallService.stopIncomingCallWatcher();
    SecurityService.cancelInactivityTimer();

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}

