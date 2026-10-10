import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoofus_flutter/models/media.dart';
import 'package:twoofus_flutter/models/message.dart';
import 'package:twoofus_flutter/services/e2ee_service.dart';
import 'package:twoofus_flutter/theme/app_theme.dart';
import 'package:twoofus_flutter/theme/theme_controller.dart';
import 'package:twoofus_flutter/widgets/chat_media_bubble.dart';
import 'package:twoofus_flutter/screens/partner_profile_screen.dart';

// 1x1 transparent PNG bytes for valid image rendering
final Uint8List kValidPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 1: Media Roundtrip & Decryption Verification', () {
    test('1. End-to-end file encryption and decryption roundtrip', () async {
      await E2EEService.initialize();
      final senderPubKey = E2EEService.myPublicKey!;
      expect(senderPubKey, isNotEmpty);

      // Temporary file for encryption
      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_image.png');
      await testFile.writeAsBytes(kValidPngBytes);

      // Encrypt file using sender's own pub key (as loopback peer)
      final payload = await E2EEService.encryptFile(testFile, senderPubKey);
      expect(payload, isNotNull);
      expect(payload!.encryptedBytes, isNot(equals(kValidPngBytes)));
      expect(payload.nonce, isNotEmpty);
      expect(payload.encryptedMediaKey, isNotEmpty);

      // Decrypt file bytes using same pub key
      final decrypted = await E2EEService.decryptMediaBytes(
        encryptedFileBytes: Uint8List.fromList(payload.encryptedBytes),
        encryptedMediaKeyBundleJson: payload.encryptedMediaKey,
        nonceBase64: payload.nonce,
        remotePublicKeyBase64: senderPubKey,
      );

      expect(decrypted, isNotNull);
      expect(decrypted, equals(kValidPngBytes));

      if (testFile.existsSync()) {
        testFile.deleteSync();
      }
    });

    test('1b. Real two-account key encapsulation and decapsulation roundtrip', () async {
      // 1. Initialize Alice (User 1)
      await E2EEService.initialize(userId: 1);
      final alicePubKey = E2EEService.myPublicKey!;
      expect(alicePubKey, isNotEmpty);

      // 2. Initialize Bob (User 2)
      await E2EEService.initialize(userId: 2);
      final bobPubKey = E2EEService.myPublicKey!;
      expect(bobPubKey, isNotEmpty);
      expect(alicePubKey, isNot(equals(bobPubKey)), reason: 'Two separate accounts must have distinct keypairs');

      // Temporary file for encryption
      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/two_account_test.png');
      await testFile.writeAsBytes(kValidPngBytes);

      // Alice sends to Bob: switch to Alice session and encrypt for Bob
      await E2EEService.initialize(userId: 1);
      final payload = await E2EEService.encryptFile(testFile, bobPubKey);
      expect(payload, isNotNull);

      // Bob receives and decrypts payload from Alice: switch to Bob session
      await E2EEService.initialize(userId: 2);
      final bobDecrypted = await E2EEService.decryptMediaBytes(
        encryptedFileBytes: Uint8List.fromList(payload!.encryptedBytes),
        encryptedMediaKeyBundleJson: payload.encryptedMediaKey,
        nonceBase64: payload.nonce,
        remotePublicKeyBase64: alicePubKey,
      );
      expect(bobDecrypted, isNotNull);
      expect(bobDecrypted, equals(kValidPngBytes));

      // Alice views her own sent message in chat: switch to Alice session
      await E2EEService.initialize(userId: 1);
      final aliceDecrypted = await E2EEService.decryptMediaBytes(
        encryptedFileBytes: Uint8List.fromList(payload.encryptedBytes),
        encryptedMediaKeyBundleJson: payload.encryptedMediaKey,
        nonceBase64: payload.nonce,
        remotePublicKeyBase64: bobPubKey,
      );
      expect(aliceDecrypted, isNotNull);
      expect(aliceDecrypted, equals(kValidPngBytes));

      // Attempting to decrypt with an attacker/unrelated key (User 3) returns null
      await E2EEService.initialize(userId: 3);
      final charlieDecrypted = await E2EEService.decryptMediaBytes(
        encryptedFileBytes: Uint8List.fromList(payload.encryptedBytes),
        encryptedMediaKeyBundleJson: payload.encryptedMediaKey,
        nonceBase64: payload.nonce,
        remotePublicKeyBase64: alicePubKey,
      );
      expect(charlieDecrypted, isNull);

      if (testFile.existsSync()) {
        testFile.deleteSync();
      }
    });

    test('2. Decryption with invalid/corrupted key returns null', () async {
      await E2EEService.initialize();
      final senderPubKey = E2EEService.myPublicKey!;

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_image2.png');
      await testFile.writeAsBytes(kValidPngBytes);

      final payload = await E2EEService.encryptFile(testFile, senderPubKey);
      expect(payload, isNotNull);

      // Attempt decrypt with corrupted key bundle
      final corruptedBundle = jsonEncode({'k': base64Encode(utf8.encode('badkey')), 'n': payload!.nonce});
      final decrypted = await E2EEService.decryptMediaBytes(
        encryptedFileBytes: Uint8List.fromList(payload.encryptedBytes),
        encryptedMediaKeyBundleJson: corruptedBundle,
        nonceBase64: payload.nonce,
        remotePublicKeyBase64: senderPubKey,
      );

      expect(decrypted, isNull);

      if (testFile.existsSync()) {
        testFile.deleteSync();
      }
    });

    testWidgets('3. AuthenticatedImage renders loading skeleton while loading', (tester) async {
      final media = MediaItem(
        id: 999,
        senderId: 1,
        receiverId: 2,
        originalFilename: 'photo.png',
        storedFilename: 'stored_photo.png',
        mediaType: 'image',
        mimeType: 'image/png',
        fileSize: 100,
        storagePath: 'media/images/photo.png',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.buildThemeData(AppTheme.defaultTheme),
          home: Scaffold(
            body: AuthenticatedImage(
              url: 'http://127.0.0.1:54321/pending.png',
              token: 'test_token',
              media: media,
            ),
          ),
        ),
      );

      expect(find.byType(AuthenticatedImage), findsOneWidget);
    });

    testWidgets('4. AuthenticatedImage renders "Couldn\'t load" and tap-to-retry on error', (tester) async {
      final media = MediaItem(
        id: 999,
        senderId: 1,
        receiverId: 2,
        originalFilename: 'photo.png',
        storedFilename: 'stored_photo.png',
        mediaType: 'image',
        mimeType: 'image/png',
        fileSize: 100,
        storagePath: 'media/images/photo.png',
        isEncrypted: true,
        encryptedMediaKey: '{"k":"bad","n":"bad"}',
        encryptionNonce: base64Encode(List.filled(12, 0)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.buildThemeData(AppTheme.defaultTheme),
          home: Scaffold(
            body: AuthenticatedImage(
              url: 'http://127.0.0.1:54321/error.png',
              token: 'test_token',
              media: media,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Required UI: Neutral placeholder, "Couldn't load" caption, tap to retry
      expect(find.text("Couldn't load"), findsOneWidget);
      expect(find.text("Tap to retry"), findsOneWidget);
    });

    testWidgets('5. PartnerProfileScreen Docs tab count mismatch verification', (tester) async {
      // Simulate 6 long chat messages with URLs or > 120 chars, but 0 attached files
      final sampleMessages = [
        Message(id: 1, senderId: 1, receiverId: 2, content: "https://example.com/first-link", createdAt: DateTime.now()),
        Message(id: 2, senderId: 1, receiverId: 2, content: "https://example.com/second-link", createdAt: DateTime.now()),
        Message(id: 3, senderId: 2, receiverId: 1, content: "This is a long chat message explaining our plans for the weekend which exceeds one hundred and twenty characters in length totally.", createdAt: DateTime.now()),
        Message(id: 4, senderId: 1, receiverId: 2, content: "Another very long message about our favorite vacation memory that also happens to exceed the character length limit set in the code.", createdAt: DateTime.now()),
        Message(id: 5, senderId: 2, receiverId: 1, content: "```flutter void main() {}``` code snippet message", createdAt: DateTime.now()),
        Message(id: 6, senderId: 1, receiverId: 2, content: "https://github.com/project/twoofus", createdAt: DateTime.now()),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.buildThemeData(AppTheme.defaultTheme),
          home: PartnerProfileScreen(
            partnerId: 2,
            partnerName: "Test Partner",
            messages: sampleMessages,
            memories: const [],
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Docs tab must NOT show (6) when there are 0 document files attached!
      // It should display Docs (0).
      expect(find.text("Docs (6)"), findsNothing);
      expect(find.text("Docs (0)"), findsOneWidget);
    });

    test('6. E2EEService tracks partner key change warning and revokes verification', () async {
      SharedPreferences.setMockInitialValues({
        'e2ee_verified_99': true,
        'e2ee_partner_pubkey_99': 'initial_partner_key_base64',
      });

      expect(await E2EEService.isPartnerVerified(99), isTrue);
      expect(E2EEService.hasKeyChangedRecently(99), isFalse);

      // Verify that changing partner public key revokes verification status
      await E2EEService.setPartnerVerified(99, false);
      expect(await E2EEService.isPartnerVerified(99), isFalse);

      E2EEService.clearKeyChangedWarning(99);
      expect(E2EEService.hasKeyChangedRecently(99), isFalse);
    });
  });
}
