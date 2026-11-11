import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/e2ee_service.dart';
import '../services/call_service.dart';
import '../services/fcm_client_service.dart';

/// Session manages authentication state.
///
/// Sensitive secrets (JWT token) are stored exclusively in [FlutterSecureStorage].
/// Non-sensitive session metadata (userId, username, email, cached partner info)
/// are stored in [SharedPreferences] for fast synchronous-style access.
///
/// Upgrade path: on first access after an app update, any token that was
/// previously saved in SharedPreferences is migrated to secure storage and
/// the plaintext copy is deleted.
class Session {
  static const _storage = FlutterSecureStorage();

  // SharedPreferences keys (non-sensitive metadata only)
  static const String _kUserId = "user_id";
  static const String _kToken = "token"; // legacy key — now only used for migration purge
  static const String _kUsername = "username";
  static const String _kEmail = "email";
  static const String _kCachedPartnerId = "cached_partner_id";
  static const String _kCachedPartnerName = "cached_partner_name";

  // FlutterSecureStorage key for the JWT
  static const String _kSecureToken = "secure_token";

  // ── Getters ───────────────────────────────────────────────────────────────

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kUserId);
  }

  /// Returns the JWT access token from [FlutterSecureStorage].
  /// Also handles one-time migration from [SharedPreferences] for users
  /// upgrading from an older app version.
  static Future<String?> getToken() async {
    try {
      // Primary: read from secure storage
      final secureToken = await _storage.read(key: _kSecureToken);
      if (secureToken != null && secureToken.isNotEmpty) {
        return secureToken;
      }

      // Migration: check if a token was saved in SharedPreferences by an
      // older version of the app and move it into secure storage.
      final prefs = await SharedPreferences.getInstance();
      final legacyToken = prefs.getString(_kToken);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        debugPrint('[Session] Migrating JWT from SharedPreferences → FlutterSecureStorage');
        await _storage.write(key: _kSecureToken, value: legacyToken);
        await prefs.remove(_kToken);
        return legacyToken;
      }
    } catch (e) {
      debugPrint('[Session] getToken error: $e');
    }
    return null;
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUsername);
  }

  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEmail);
  }

  static Future<int?> getCachedPartnerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCachedPartnerId);
  }

  static Future<String?> getCachedPartnerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCachedPartnerName);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    final userId = await getUserId();
    return token != null && token.isNotEmpty && userId != null;
  }

  // ── Writers ───────────────────────────────────────────────────────────────

  static Future<void> saveLogin({
    required String token,
    required int userId,
    required String username,
    required String email,
  }) async {
    // Store JWT exclusively in FlutterSecureStorage
    try {
      await _storage.write(key: _kSecureToken, value: token);
    } catch (e) {
      debugPrint('[Session] saveLogin: failed to write to secure storage: $e');
    }

    // Non-sensitive metadata goes into SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUserId, userId);
    await prefs.setString(_kUsername, username);
    await prefs.setString(_kEmail, email);

    // Ensure no plaintext token leaks in SharedPreferences
    await prefs.remove(_kToken);

    FcmClientService.syncTokenIfLoggedIn();
  }

  static Future<void> savePartner(int partnerId, String partnerName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCachedPartnerId, partnerId);
    await prefs.setString(_kCachedPartnerName, partnerName);
  }

  static Future<void> clearPartner() async {
    CallService.stopIncomingCallWatcher();
    E2EEService.clearSessionCaches();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedPartnerId);
    await prefs.remove(_kCachedPartnerName);
  }

  static Future<void> logout() async {
    CallService.stopIncomingCallWatcher();
    E2EEService.clearSessionCaches();

    // Delete JWT from secure storage
    try {
      await _storage.delete(key: _kSecureToken);
    } catch (e) {
      debugPrint('[Session] logout: failed to delete secure token: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserId);
    await prefs.remove(_kToken); // purge any stale legacy plaintext token
    await prefs.remove(_kUsername);
    await prefs.remove(_kEmail);
    await prefs.remove(_kCachedPartnerId);
    await prefs.remove(_kCachedPartnerName);
  }

  static Future<void> clear() => logout();
}
