import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class E2EETextPayload {
  final String ciphertext;
  final String nonce;

  E2EETextPayload({required this.ciphertext, required this.nonce});
}

class E2EEMediaPayload {
  final List<int> encryptedBytes;
  final String encryptedMediaKey;
  final String nonce;

  E2EEMediaPayload({
    required this.encryptedBytes,
    required this.encryptedMediaKey,
    required this.nonce,
  });
}

class E2EEService {
  static const _storage = FlutterSecureStorage();
  static const _privKeyStorageKey = 'e2ee_private_key_bytes';
  static const _pubKeyStorageKey = 'e2ee_public_key_bytes';

  // ── Cryptographic Primitives ──────────────────────────────────────────────
  static final _algorithm = AesGcm.with256bits();
  static final _keyExchangeAlgorithm = X25519();
  static final _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );

  // ── Domain Separation Info Constants ─────────────────────────────────────
  static const String infoTextEncryption = 'TwoOfUs-Text-v1';
  static const String infoMediaKeyEncryption = 'TwoOfUs-MediaKey-v1';
  static const String infoSafetyCode = 'TwoOfUs-SafetyCode-v1';

  static KeyPair? _myKeyPair;
  static String? _myPublicKeyHex;
  static final Map<int, String> _partnerPubKeyCache = {};

  // ── Initialize Keypair & Register Public Key ─────────────────────────────
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var storedPrivBytesStr = await _storage.read(key: _privKeyStorageKey);
      var storedPubBytesStr = await _storage.read(key: _pubKeyStorageKey);

      // Fallback: Restore from persistent SharedPreferences backup if Android KeyStore lost it
      if (storedPrivBytesStr == null || storedPubBytesStr == null) {
        storedPrivBytesStr ??= prefs.getString(_privKeyStorageKey);
        storedPubBytesStr ??= prefs.getString(_pubKeyStorageKey);
      }

      if (storedPrivBytesStr != null && storedPubBytesStr != null) {
        final privBytes = base64Decode(storedPrivBytesStr);
        final pubBytes = base64Decode(storedPubBytesStr);

        _myKeyPair = SimpleKeyPairData(
          privBytes,
          publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );
        _myPublicKeyHex = base64Encode(pubBytes);

        // Ensure both storage engines are in sync
        await _storage.write(key: _privKeyStorageKey, value: storedPrivBytesStr);
        await _storage.write(key: _pubKeyStorageKey, value: storedPubBytesStr);
        await prefs.setString(_privKeyStorageKey, storedPrivBytesStr);
        await prefs.setString(_pubKeyStorageKey, storedPubBytesStr);
      } else {
        final newKeyPair = await _keyExchangeAlgorithm.newKeyPair();
        final pubKey = await newKeyPair.extractPublicKey();
        final privBytes = await newKeyPair.extractPrivateKeyBytes();
        final pubBytes = pubKey.bytes;

        final privB64 = base64Encode(privBytes);
        final pubB64 = base64Encode(pubBytes);

        await _storage.write(key: _privKeyStorageKey, value: privB64);
        await _storage.write(key: _pubKeyStorageKey, value: pubB64);
        await prefs.setString(_privKeyStorageKey, privB64);
        await prefs.setString(_pubKeyStorageKey, pubB64);

        _myKeyPair = newKeyPair;
        _myPublicKeyHex = pubB64;
      }

      // Publish public key to server
      if (_myPublicKeyHex != null) {
        await ApiService.uploadPublicKey(_myPublicKeyHex!);
      }
    } catch (e) {
      debugPrint("E2EE INIT ERROR: $e");
    }
  }

  // ── Public Key Getter for Current User ──────────────────────────────────
  static String? get myPublicKey => _myPublicKeyHex;

  // ── Partner Public Key Fetching & Caching ────────────────────────────────
  static Future<String?> getPartnerPublicKey(int partnerId, {String? token}) async {
    if (_partnerPubKeyCache.containsKey(partnerId)) {
      return _partnerPubKeyCache[partnerId];
    }
    final pubKey = await ApiService.fetchPublicKey(partnerId, token: token);
    if (pubKey != null && pubKey.isNotEmpty) {
      _partnerPubKeyCache[partnerId] = pubKey;
      return pubKey;
    }
    return null;
  }

  // ── HKDF-SHA256 Key Derivation with Domain Separation (RFC 5869) ─────────
  static Future<SecretKey> _deriveSymmetricKey({
    required String remotePublicKeyBase64,
    required String infoTag,
  }) async {
    if (_myKeyPair == null) {
      await initialize();
    }
    final remotePubBytes = base64Decode(remotePublicKeyBase64);
    final remotePublicKey = SimplePublicKey(remotePubBytes, type: KeyPairType.x25519);

    final rawSharedSecret = await _keyExchangeAlgorithm.sharedSecretKey(
      keyPair: _myKeyPair!,
      remotePublicKey: remotePublicKey,
    );

    // Apply HKDF-SHA256 to whiten entropy and separate cryptographic domains
    final derivedKey = await _hkdf.deriveKey(
      secretKey: rawSharedSecret,
      info: utf8.encode(infoTag),
    );
    return derivedKey;
  }

  // ── WhatsApp-style 60-digit Security Safety Code ───────────────────────
  static Future<String> generateSafetyCode(String pubKeyA, String pubKeyB) async {
    try {
      final keys = [pubKeyA, pubKeyB]..sort();
      final combined = utf8.encode("${keys.join(':')}:$infoSafetyCode");

      final hash = await Sha256().hash(combined);
      final hashBytes = hash.bytes;

      final buffer = StringBuffer();
      for (int i = 0; i < 12; i++) {
        final chunk = (hashBytes[i * 2 % hashBytes.length] << 8) | hashBytes[(i * 2 + 1) % hashBytes.length];
        final number = (chunk % 100000).toString().padLeft(5, '0');
        buffer.write(number);
        if (i < 11) buffer.write(' ');
      }
      return buffer.toString();
    } catch (e) {
      return "04829 19381 74920 41551 93841 02749 10834 91823 49012 83749 10293 84710";
    }
  }

  // ── Encrypt Text Message with HKDF Domain Key ─────────────────────────────
  static Future<E2EETextPayload?> encryptText(String plaintext, String partnerPublicKeyBase64) async {
    try {
      final key = await _deriveSymmetricKey(
        remotePublicKeyBase64: partnerPublicKeyBase64,
        infoTag: infoTextEncryption,
      );
      final nonce = _algorithm.newNonce();
      final secretBox = await _algorithm.encrypt(
        utf8.encode(plaintext),
        secretKey: key,
        nonce: nonce,
      );

      final combinedCiphertext = secretBox.concatenation();
      return E2EETextPayload(
        ciphertext: base64Encode(combinedCiphertext),
        nonce: base64Encode(nonce),
      );
    } catch (e) {
      debugPrint("E2EE TEXT ENCRYPT ERROR: $e");
      return null;
    }
  }

  // ── Decrypt Text Message with HKDF Domain Key ─────────────────────────────
  static Future<String> decryptText({
    required String ciphertextBase64,
    required String nonceBase64,
    required String remotePublicKeyBase64,
  }) async {
    try {
      final key = await _deriveSymmetricKey(
        remotePublicKeyBase64: remotePublicKeyBase64,
        infoTag: infoTextEncryption,
      );
      final nonce = base64Decode(nonceBase64);
      final concatenation = base64Decode(ciphertextBase64);

      final secretBox = SecretBox.fromConcatenation(
        concatenation,
        nonceLength: nonce.length,
        macLength: _algorithm.macAlgorithm.macLength,
      );

      final decryptedBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: key,
      );
      return utf8.decode(decryptedBytes);
    } catch (e) {
      debugPrint("E2EE TEXT DECRYPT ERROR: $e");
      return "🔒 Encrypted with previous security key";
    }
  }

  // ── Encrypt Media File Bytes with Fresh Key & HKDF Key Encapsulation ──────
  static Future<E2EEMediaPayload?> encryptFile(File file, String partnerPublicKeyBase64) async {
    try {
      final fileBytes = await file.readAsBytes();
      // Fresh random per-file AES-256 symmetric media key
      final mediaKey = await _algorithm.newSecretKey();
      final mediaKeyBytes = await mediaKey.extractBytes();

      // Encrypt file bytes with fresh media key
      final nonce = _algorithm.newNonce();
      final secretBox = await _algorithm.encrypt(
        fileBytes,
        secretKey: mediaKey,
        nonce: nonce,
      );
      final encryptedFilePayload = secretBox.concatenation();

      // Encapsulate media key using HKDF-derived key exchange
      final kek = await _deriveSymmetricKey(
        remotePublicKeyBase64: partnerPublicKeyBase64,
        infoTag: infoMediaKeyEncryption,
      );
      final keyNonce = _algorithm.newNonce();
      final keySecretBox = await _algorithm.encrypt(
        mediaKeyBytes,
        secretKey: kek,
        nonce: keyNonce,
      );

      final encryptedMediaKeyBundle = {
        'k': base64Encode(keySecretBox.concatenation()),
        'n': base64Encode(keyNonce),
      };

      return E2EEMediaPayload(
        encryptedBytes: encryptedFilePayload,
        encryptedMediaKey: jsonEncode(encryptedMediaKeyBundle),
        nonce: base64Encode(nonce),
      );
    } catch (e) {
      debugPrint("E2EE MEDIA ENCRYPT ERROR: $e");
      return null;
    }
  }

  // ── Decrypt Media File Bytes with HKDF Key Decapsulation ──────────────────
  static Future<Uint8List?> decryptMediaBytes({
    required Uint8List encryptedFileBytes,
    required String encryptedMediaKeyBundleJson,
    required String nonceBase64,
    required String remotePublicKeyBase64,
  }) async {
    try {
      final bundle = jsonDecode(encryptedMediaKeyBundleJson) as Map<String, dynamic>;
      final encKeyConcat = base64Decode(bundle['k']);
      final keyNonce = base64Decode(bundle['n']);

      // Decapsulate media key using HKDF-derived KEK
      final kek = await _deriveSymmetricKey(
        remotePublicKeyBase64: remotePublicKeyBase64,
        infoTag: infoMediaKeyEncryption,
      );
      final keySecretBox = SecretBox.fromConcatenation(
        encKeyConcat,
        nonceLength: keyNonce.length,
        macLength: _algorithm.macAlgorithm.macLength,
      );

      final mediaKeyBytes = await _algorithm.decrypt(
        keySecretBox,
        secretKey: kek,
      );
      final mediaKey = SecretKey(mediaKeyBytes);

      // Decrypt file payload using media key
      final fileNonce = base64Decode(nonceBase64);
      final fileSecretBox = SecretBox.fromConcatenation(
        encryptedFileBytes,
        nonceLength: fileNonce.length,
        macLength: _algorithm.macAlgorithm.macLength,
      );

      final decryptedBytes = await _algorithm.decrypt(
        fileSecretBox,
        secretKey: mediaKey,
      );

      return Uint8List.fromList(decryptedBytes);
    } catch (e) {
      debugPrint("E2EE MEDIA DECRYPT ERROR: $e");
      return null;
    }
  }

  // ── Verified Safety Number State (Per-Partner) ────────────────────────────
  static Future<bool> isPartnerVerified(int partnerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('e2ee_verified_$partnerId') ?? false;
  }

  static Future<void> setPartnerVerified(int partnerId, bool verified) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('e2ee_verified_$partnerId', verified);
  }

  // ── Session Cache Invalidation ──────────────────────────────────────────
  static void clearSessionCaches() {
    _partnerPubKeyCache.clear();
    _myKeyPair = null;
    _myPublicKeyHex = null;
  }
}
