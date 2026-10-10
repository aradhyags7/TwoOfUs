import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoofus_flutter/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Update Required Fail-Closed Handling', () {
    test('isUpdateRequiredError detects exact backend error strings from main.py', () {
      expect(
        ApiService.isUpdateRequiredError(
          '{"detail":"Unencrypted user content is rejected. End-to-end encryption is required."}',
        ),
        isTrue,
      );

      expect(
        ApiService.isUpdateRequiredError(
          '{"detail":"Unencrypted media uploads are rejected. End-to-end encryption is required."}',
        ),
        isTrue,
      );

      expect(
        ApiService.isUpdateRequiredError(
          '{"detail":"Encrypted media uploads cannot have empty encrypted_media_key"}',
        ),
        isTrue,
      );

      expect(
        ApiService.isUpdateRequiredError(
          '{"detail":"Encrypted messages must include a valid encryption nonce"}',
        ),
        isTrue,
      );

      expect(
        ApiService.isUpdateRequiredError('{"detail":"Invalid username or password"}'),
        isFalse,
      );

      expect(
        ApiService.isUpdateRequiredError('{"detail":"User not found"}'),
        isFalse,
      );
    });

    test('checkFailClosedError invokes onUpdateRequired callback', () {
      bool callbackInvoked = false;
      ApiService.onUpdateRequired = () {
        callbackInvoked = true;
      };

      // Unrelated 400
      ApiService.checkFailClosedError(400, '{"detail":"Bad Request: missing field"}');
      expect(callbackInvoked, isFalse);

      // Status 500 with matching string should not trigger 400 handler
      ApiService.checkFailClosedError(
        500,
        '{"detail":"Unencrypted user content is rejected. End-to-end encryption is required."}',
      );
      expect(callbackInvoked, isFalse);

      // Real fail-closed 400
      ApiService.checkFailClosedError(
        400,
        '{"detail":"Unencrypted user content is rejected. End-to-end encryption is required."}',
      );
      expect(callbackInvoked, isTrue);

      ApiService.onUpdateRequired = null;
    });

    testWidgets('showUpdateRequiredDialog renders clear dialog with explanation and dismisses on OK',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () {
                      ApiService.showUpdateRequiredDialog(context);
                    },
                    child: const Text('Trigger Update Dialog'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Update Required'), findsNothing);

      await tester.tap(find.text('Trigger Update Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Update Required'), findsOneWidget);
      expect(
        find.textContaining('This version of TwoOfUs is outdated'),
        findsOneWidget,
      );
      expect(find.text('OK'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Update Required'), findsNothing);
    });
  });
}
