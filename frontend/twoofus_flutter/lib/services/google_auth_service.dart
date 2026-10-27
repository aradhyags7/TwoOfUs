import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_service.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// Triggers Google account selection, gets the Google ID token, and sends it to /auth/google
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

      if (idToken == null || idToken.trim().isEmpty) {
        return {
          "error": "Google did not provide an ID token. Please verify that your Google Cloud OAuth Client ID is registered with your app's SHA-1 fingerprint.",
        };
      }

      final result = await ApiService.googleSignIn(idToken);
      return result;
    } catch (e) {
      debugPrint("[GoogleAuthService] Google Sign-In error: $e");
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
