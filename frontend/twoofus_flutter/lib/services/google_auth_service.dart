import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_service.dart';

class GoogleAuthService {
  /// Optional OAuth 2.0 Web Client ID from Google Cloud / Firebase Console.
  /// If provided, Google Play Services generates an OpenID Connect idToken.
  static const String? serverClientId = null;

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: serverClientId,
  );

  /// Triggers Google account selection, obtains Google ID token or Access token,
  /// and authenticates with backend /auth/google
  static Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      // Disconnect or sign out first if previous session was cached to ensure account chooser opens
      try {
        if (await _googleSignIn.isSignedIn()) {
          await _googleSignIn.signOut();
        }
      } catch (_) {}

      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        // User cancelled the prompt
        return null;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;
      final String? accessToken = auth.accessToken;

      if ((idToken == null || idToken.trim().isEmpty) &&
          (accessToken == null || accessToken.trim().isEmpty)) {
        return {
          "error": "Google did not provide authentication tokens. Please ensure Google Play Services is configured.",
        };
      }

      final result = await ApiService.googleSignIn(
        idToken: idToken,
        accessToken: accessToken,
      );
      return result;
    } catch (e) {
      debugPrint("[GoogleAuthService] Google Sign-In error: $e");
      final errStr = e.toString();
      if (errStr.contains("10") || errStr.contains("DEVELOPER_ERROR")) {
        return {
          "error": "Google Sign-In setup required (Code 10: Developer Error).\nEnsure your debug SHA-1 (EA:C9:53:FB:9D:CD:1B:91:A1:32:2E:FA:5D:F0:0E:4D:BF:44:B3:A2) and package (com.example.twoofus_flutter) are added to Google Cloud / Firebase Console.",
        };
      } else if (errStr.contains("12500")) {
        return {
          "error": "Google Sign-In failed (Code 12500). Please check your Google account and OAuth consent screen.",
        };
      } else if (errStr.contains("channel-error") || errStr.contains("GoogleSignInApi.init")) {
        return {
          "error": "Native plugin channel not connected. Please stop and re-launch 'flutter run'.",
        };
      }
      return {
        "error": "Google sign-in encountered an error: $e",
      };
    }
  }

  /// Signs out of the Google session
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}
