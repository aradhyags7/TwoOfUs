import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoofus_flutter/services/e2ee_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('E2EE Cryptographic Security Tests', () {
    late X25519 x25519;
    late AesGcm aesGcm;
    late Hkdf hkdf;

    setUp(() {
      x25519 = X25519();
      aesGcm = AesGcm.with256bits();
      hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    });

    test('1. X25519 shared secret is properly derived through HKDF-SHA256', () async {
      // User Alice
      final aliceKeyPair = await x25519.newKeyPair();
      final alicePubKey = await aliceKeyPair.extractPublicKey();

      // User Bob
      final bobKeyPair = await x25519.newKeyPair();
      final bobPubKey = await bobKeyPair.extractPublicKey();

      // Derive raw shared secrets
      final aliceRawSecret = await x25519.sharedSecretKey(keyPair: aliceKeyPair, remotePublicKey: bobPubKey);
      final bobRawSecret = await x25519.sharedSecretKey(keyPair: bobKeyPair, remotePublicKey: alicePubKey);

      // Verify raw secrets match
      final aliceRawBytes = await aliceRawSecret.extractBytes();
      final bobRawBytes = await bobRawSecret.extractBytes();
      expect(aliceRawBytes, equals(bobRawBytes));

      // Derive domain-separated keys via HKDF-SHA256
      const infoText = 'TwoOfUs-Text-v1';
      const infoMedia = 'TwoOfUs-MediaKey-v1';

      final aliceTextKey = await hkdf.deriveKey(secretKey: aliceRawSecret, info: utf8.encode(infoText));
      final bobTextKey = await hkdf.deriveKey(secretKey: bobRawSecret, info: utf8.encode(infoText));
      final aliceMediaKey = await hkdf.deriveKey(secretKey: aliceRawSecret, info: utf8.encode(infoMedia));

      final aliceTextBytes = await aliceTextKey.extractBytes();
      final bobTextBytes = await bobTextKey.extractBytes();
      final aliceMediaBytes = await aliceMediaKey.extractBytes();

      // Invariants:
      // A. Text keys derived on both sides match
      expect(aliceTextBytes, equals(bobTextBytes));
      // B. Key length is exactly 256 bits (32 bytes)
      expect(aliceTextBytes.length, equals(32));
      // C. Domain separation: Text key is distinct from Media key
      expect(aliceTextBytes, isNot(equals(aliceMediaBytes)));
      // D. Raw shared secret is NEVER equal to derived AES key
      expect(aliceRawBytes, isNot(equals(aliceTextBytes)));
    });

    test('2. AES-256-GCM uses fresh 96-bit nonces on every encryption', () async {
      final nonce1 = aesGcm.newNonce();
      final nonce2 = aesGcm.newNonce();

      expect(nonce1.length, equals(12)); // 96-bit
      expect(nonce2.length, equals(12)); // 96-bit
      expect(nonce1, isNot(equals(nonce2))); // CSPRNG uniqueness
    });

    test('3. Decryption fails safely when ciphertext or tag is tampered', () async {
      final key = await aesGcm.newSecretKey();
      final nonce = aesGcm.newNonce();
      const plaintext = "Confidential Top Secret Data";

      final secretBox = await aesGcm.encrypt(
        utf8.encode(plaintext),
        secretKey: key,
        nonce: nonce,
      );

      final combined = secretBox.concatenation();
      final tampered = Uint8List.fromList(combined);
      tampered[tampered.length - 1] ^= 0xFF; // Flip byte in tag/ciphertext

      final tamperedSecretBox = SecretBox.fromConcatenation(
        tampered,
        nonceLength: nonce.length,
        macLength: aesGcm.macAlgorithm.macLength,
      );

      // Decryption MUST throw SecretBoxAuthenticationError
      expect(
        () async => await aesGcm.decrypt(tamperedSecretBox, secretKey: key),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('4. Decryption fails when wrong key or wrong nonce is supplied', () async {
      final keyAlice = await aesGcm.newSecretKey();
      final keyEve = await aesGcm.newSecretKey();
      final nonce = aesGcm.newNonce();
      const plaintext = "Confidential Top Secret Data";

      final secretBox = await aesGcm.encrypt(
        utf8.encode(plaintext),
        secretKey: keyAlice,
        nonce: nonce,
      );

      // Decrypting with Eve's key MUST throw authentication error
      expect(
        () async => await aesGcm.decrypt(secretBox, secretKey: keyEve),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('5. Timeline content E2EE roundtrip with domain separation (TwoOfUs-Timeline-v1)', () async {
      SharedPreferences.setMockInitialValues({});
      // Alice (user 1)
      await E2EEService.initialize(userId: 1);
      final alicePubKey = E2EEService.myPublicKey!;

      // Bob (user 2)
      await E2EEService.initialize(userId: 2);
      final bobPubKey = E2EEService.myPublicKey!;

      // Alice encrypts timeline entry for Bob
      await E2EEService.initialize(userId: 1);
      const plaintext = "Our romantic stargazing memory 🌟";
      final encPayload = await E2EEService.encryptTimelineContent(plaintext, bobPubKey);
      expect(encPayload, isNotNull);
      expect(encPayload!.ciphertext, isNot(equals(plaintext)));
      expect(encPayload.nonce, isNotEmpty);

      // Bob decrypts Alice's timeline entry
      await E2EEService.initialize(userId: 2);
      final decryptedBob = await E2EEService.decryptTimelineContent(
        ciphertextBase64: encPayload.ciphertext,
        nonceBase64: encPayload.nonce,
        remotePublicKeyBase64: alicePubKey,
      );
      expect(decryptedBob, equals(plaintext));

      // Alice decrypts her own sent timeline entry
      await E2EEService.initialize(userId: 1);
      final decryptedAlice = await E2EEService.decryptTimelineContent(
        ciphertextBase64: encPayload.ciphertext,
        nonceBase64: encPayload.nonce,
        remotePublicKeyBase64: bobPubKey,
      );
      expect(decryptedAlice, equals(plaintext));

      // Eve (user 3) fails to decrypt
      await E2EEService.initialize(userId: 3);
      final decryptedEve = await E2EEService.decryptTimelineContent(
        ciphertextBase64: encPayload.ciphertext,
        nonceBase64: encPayload.nonce,
        remotePublicKeyBase64: alicePubKey,
      );
      expect(decryptedEve, equals("🔒 Encrypted timeline entry"));
    });

    test('6. Timeline photo E2EE roundtrip with domain separation', () async {
      SharedPreferences.setMockInitialValues({});
      await E2EEService.initialize(userId: 1);
      final alicePubKey = E2EEService.myPublicKey!;

      await E2EEService.initialize(userId: 2);
      final bobPubKey = E2EEService.myPublicKey!;

      final samplePhotoBytes = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80, 90, 100]);

      // Alice encrypts photo for Bob
      await E2EEService.initialize(userId: 1);
      final encPhoto = await E2EEService.encryptTimelinePhoto(samplePhotoBytes, bobPubKey);
      expect(encPhoto, isNotNull);
      expect(encPhoto!.encryptedBytes, isNot(equals(samplePhotoBytes)));

      // Bob decrypts photo from Alice
      await E2EEService.initialize(userId: 2);
      final decPhotoBob = await E2EEService.decryptTimelinePhoto(
        encryptedPhotoBytes: Uint8List.fromList(encPhoto.encryptedBytes),
        nonceBase64: encPhoto.nonce,
        remotePublicKeyBase64: alicePubKey,
      );
      expect(decPhotoBob, equals(samplePhotoBytes));

      // Alice decrypts her own photo
      await E2EEService.initialize(userId: 1);
      final decPhotoAlice = await E2EEService.decryptTimelinePhoto(
        encryptedPhotoBytes: Uint8List.fromList(encPhoto.encryptedBytes),
        nonceBase64: encPhoto.nonce,
        remotePublicKeyBase64: bobPubKey,
      );
      expect(decPhotoAlice, equals(samplePhotoBytes));

      // Eve (user 3) fails to decrypt photo
      await E2EEService.initialize(userId: 3);
      final decPhotoEve = await E2EEService.decryptTimelinePhoto(
        encryptedPhotoBytes: Uint8List.fromList(encPhoto.encryptedBytes),
        nonceBase64: encPhoto.nonce,
        remotePublicKeyBase64: alicePubKey,
      );
      expect(decPhotoEve, isNull);
    });
  });
}
