import 'package:shared_preferences/shared_preferences.dart';
import '../services/e2ee_service.dart';
import '../services/call_service.dart';

class Session {
  static const String _kUserId = "user_id";
  static const String _kToken = "token";
  static const String _kUsername = "username";
  static const String _kEmail = "email";
  static const String _kCachedPartnerId = "cached_partner_id";
  static const String _kCachedPartnerName = "cached_partner_name";

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kUserId);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kToken);
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

  static Future<void> saveLogin({
    required String token,
    required int userId,
    required String username,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setInt(_kUserId, userId);
    await prefs.setString(_kUsername, username);
    await prefs.setString(_kEmail, email);
  }

  static Future<void> savePartner(int partnerId, String partnerName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCachedPartnerId, partnerId);
    await prefs.setString(_kCachedPartnerName, partnerName);
  }

  static Future<void> clearPartner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedPartnerId);
    await prefs.remove(_kCachedPartnerName);
  }

  static Future<void> logout() async {
    CallService.stopIncomingCallWatcher();
    E2EEService.clearSessionCaches();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserId);
    await prefs.remove(_kToken);
    await prefs.remove(_kUsername);
    await prefs.remove(_kEmail);
    await prefs.remove(_kCachedPartnerId);
    await prefs.remove(_kCachedPartnerName);
  }

  static Future<void> clear() => logout();
}