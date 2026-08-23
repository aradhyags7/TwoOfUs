import 'package:shared_preferences/shared_preferences.dart';
import '../services/e2ee_service.dart';
import '../services/call_service.dart';

class Session {
  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt("user_id");
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("token");
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("username");
  }

  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("email");
  }

  static Future<void> logout() async {
    CallService.stopIncomingCallWatcher();
    E2EEService.clearSessionCaches();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("user_id");
    await prefs.remove("token");
    await prefs.remove("username");
    await prefs.remove("email");
  }

  static Future<void> clear() => logout();
}