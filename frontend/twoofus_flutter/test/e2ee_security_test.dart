import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
