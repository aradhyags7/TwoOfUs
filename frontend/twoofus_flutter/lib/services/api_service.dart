import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/session.dart';

class ApiService {
  static const String productionServerUrl = "https://twoofus.onrender.com";
  static const String _serverPrefKey = "custom_server_base_url";
  static const String _lastWorkingPrefKey = "last_working_server_url";
  static String? _customBaseUrl;
  static String? _discoveredBaseUrl;
  static bool _isDiscovering = false;

  /// Loads configured custom server address on app startup and triggers background discovery
  static Future<void> initServerConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customBaseUrl = prefs.getString(_serverPrefKey);
      _discoveredBaseUrl = prefs.getString(_lastWorkingPrefKey);
      
      // Auto-discover in background if no custom base URL is explicitly forced
      if (_customBaseUrl == null || _customBaseUrl!.isEmpty) {
        autoDiscoverServer();
      }
    } catch (_) {}
  }

  /// Sets and persists custom backend base URL
  static Future<void> setCustomBaseUrl(String? url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (url == null || url.trim().isEmpty) {
        _customBaseUrl = null;
        await prefs.remove(_serverPrefKey);
      } else {
        String cleanUrl = url.trim();
        if (!cleanUrl.startsWith("http://") && !cleanUrl.startsWith("https://")) {
          cleanUrl = "https://$cleanUrl";
        }
        if (cleanUrl.endsWith("/")) {
          cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
        }
        _customBaseUrl = cleanUrl;
        await prefs.setString(_serverPrefKey, cleanUrl);
      }
    } catch (_) {}
  }

  /// Live test connection to backend
  static Future<bool> testConnection([String? testUrl]) async {
    try {
      String target = testUrl ?? baseUrl;
      if (!target.startsWith("http://") && !target.startsWith("https://")) {
        target = "https://$target";
      }
      if (target.endsWith("/")) {
        target = target.substring(0, target.length - 1);
      }
      final res = await http.get(Uri.parse("$target/health")).timeout(const Duration(milliseconds: 2000));
      if (res.statusCode == 200) {
        try {
          final body = jsonDecode(res.body);
          if (body is Map && (body["app"] == "TwoOfUs" || body["status"] == "ok")) {
            return true;
          }
        } catch (_) {}
      }
      final pingRes = await http.get(Uri.parse("$target/ping")).timeout(const Duration(milliseconds: 2000));
      if (pingRes.statusCode == 200) {
        try {
          final body = jsonDecode(pingRes.body);
          if (body is Map && (body["app"] == "TwoOfUs" || body["status"] == "ok")) {
            return true;
          }
        } catch (_) {}
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Fast parallel candidate probing & subnet scanning to discover server on any network
  static Future<String?> autoDiscoverServer({bool forceScan = false}) async {
    if (_isDiscovering) return _discoveredBaseUrl;
    _isDiscovering = true;
    try {
      // 1. If custom URL is explicitly set, check if it works
      if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
        if (await _probeCandidate(_customBaseUrl!)) {
          _isDiscovering = false;
          return _customBaseUrl;
        }
      }

      // 2. Fast candidate list: production cloud first, then last known, emulator, etc.
      final List<String> fastCandidates = [];
      if (_discoveredBaseUrl != null && _discoveredBaseUrl!.isNotEmpty) {
        fastCandidates.add(_discoveredBaseUrl!);
      }
      fastCandidates.addAll([
        productionServerUrl,
        "http://10.20.9.103:8000",
        "http://127.0.0.1:8000",
        "http://10.0.2.2:8000",
        "http://localhost:8000",
      ]);

      for (final candidate in fastCandidates) {
        if (await _probeCandidate(candidate, timeoutMs: 800)) {
          await _saveWorkingUrl(candidate);
          _isDiscovering = false;
          return candidate;
        }
      }

      // 3. Scan dynamic local Wi-Fi / Hotspot network interfaces
      final dynamicCandidates = <String>{};
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            final ip = addr.address;
            final lastDot = ip.lastIndexOf('.');
            if (lastDot != -1) {
              final prefix = ip.substring(0, lastDot + 1);
              // Common host / router / hotspot server IPs
              dynamicCandidates.add("http://${prefix}1:8000");
              dynamicCandidates.add("http://${prefix}2:8000");
              dynamicCandidates.add("http://${prefix}100:8000");
              dynamicCandidates.add("http://${prefix}101:8000");
              dynamicCandidates.add("http://${prefix}102:8000");
              dynamicCandidates.add("http://${prefix}103:8000");
              dynamicCandidates.add("http://${prefix}104:8000");
              dynamicCandidates.add("http://${prefix}105:8000");
              dynamicCandidates.add("http://${prefix}106:8000");
              dynamicCandidates.add("http://${prefix}107:8000");
              dynamicCandidates.add("http://${prefix}108:8000");
              dynamicCandidates.add("http://${prefix}109:8000");
              dynamicCandidates.add("http://${prefix}110:8000");
              dynamicCandidates.add("http://$ip:8000");
            }
          }
        }
      } catch (_) {}

      if (dynamicCandidates.isNotEmpty) {
        final results = await Future.wait(
          dynamicCandidates.map((url) async {
            final isAlive = await _probeCandidate(url, timeoutMs: 1000);
            return isAlive ? url : null;
          }),
        );
        for (final res in results) {
          if (res != null) {
            await _saveWorkingUrl(res);
            _isDiscovering = false;
            return res;
          }
        }
      }

      // 4. Full local subnet sweep (1-254) in concurrent chunks of 30
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            final ip = addr.address;
            final lastDot = ip.lastIndexOf('.');
            if (lastDot != -1) {
              final prefix = ip.substring(0, lastDot + 1);
              for (int start = 1; start < 255; start += 30) {
                final chunk = <String>[];
                for (int i = start; i < start + 30 && i < 255; i++) {
                  chunk.add("http://$prefix$i:8000");
                }
                final chunkResults = await Future.wait(
                  chunk.map((url) async {
                    final ok = await _probeCandidate(url, timeoutMs: 700);
                    return ok ? url : null;
                  }),
                );
                for (final found in chunkResults) {
                  if (found != null) {
                    await _saveWorkingUrl(found);
                    _isDiscovering = false;
                    return found;
                  }
                }
              }
            }
          }
        }
      } catch (_) {}

    } catch (_) {} finally {
      _isDiscovering = false;
    }
    return _discoveredBaseUrl;
  }

  static Future<bool> _probeCandidate(String url, {int timeoutMs = 900}) async {
    try {
      final res = await http.get(Uri.parse("$url/health")).timeout(Duration(milliseconds: timeoutMs));
      if (res.statusCode == 200) {
        try {
          final body = jsonDecode(res.body);
          if (body is Map && (body["app"] == "TwoOfUs" || body["status"] == "ok")) {
            return true;
          }
        } catch (_) {}
      }
      final pingRes = await http.get(Uri.parse("$url/ping")).timeout(Duration(milliseconds: timeoutMs));
      if (pingRes.statusCode == 200) {
        try {
          final body = jsonDecode(pingRes.body);
          if (body is Map && (body["app"] == "TwoOfUs" || body["status"] == "ok")) {
            return true;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }

  static Future<void> _saveWorkingUrl(String url) async {
    _discoveredBaseUrl = url;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastWorkingPrefKey, url);
    } catch (_) {}
  }

  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }
    if (_discoveredBaseUrl != null && _discoveredBaseUrl!.isNotEmpty) {
      return _discoveredBaseUrl!;
    }
    return productionServerUrl;
  }

  static Future<Map<String, String>> _authHeaders({String? token, bool json = true}) async {
    final effectiveToken = (token != null && token.isNotEmpty) ? token : (await Session.getToken() ?? '');
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    if (effectiveToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $effectiveToken';
    }
    return headers;
  }

  static const Duration defaultTimeout = Duration(seconds: 15);

  // =========================
  // LOGIN
  // =========================
  static Future<Map<String, dynamic>?> login(
    String email,
    String password,
  ) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/login'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'email': email,
            'password': password,
          }),
        ).timeout(defaultTimeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          try {
            final err = jsonDecode(response.body);
            return {"error": err["detail"] ?? "Login failed (${response.statusCode})"};
          } catch (_) {
            return {"error": "Server error (${response.statusCode})"};
          }
        }
      } catch (e) {
        if (attempt == 0) {
          // Auto-discover backend on the new network and retry immediately
          final discovered = await autoDiscoverServer();
          if (discovered != null) {
            continue;
          }
        }
        return {"error": "Cannot connect to server. Please check backend connection."};
      }
    }
    return {"error": "Cannot connect to server. Please check backend connection."};
  }

  // =========================
  // REGISTER
  // =========================
  static Future<Map<String, dynamic>?> register(
    String email,
    String username,
    String password,
  ) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/register'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'email': email,
            'username': username,
            'password': password,
          }),
        ).timeout(defaultTimeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          try {
            final err = jsonDecode(response.body);
            return {"error": err["detail"] ?? "Registration failed (${response.statusCode})"};
          } catch (_) {
            return {"error": "Server error (${response.statusCode})"};
          }
        }
      } catch (e) {
        if (attempt == 0) {
          final discovered = await autoDiscoverServer();
          if (discovered != null) {
            continue;
          }
        }
        return {"error": "Cannot connect to server. Please check backend connection."};
      }
    }
    return {"error": "Cannot connect to server. Please check backend connection."};
  }

  // =========================
  // FORGOT & RESET PASSWORD
  // =========================
  static Future<Map<String, dynamic>?> requestPasswordReset(
    String emailOrUsername,
  ) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/forgot-password'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'email_or_username': emailOrUsername,
          }),
        ).timeout(defaultTimeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          try {
            final err = jsonDecode(response.body);
            return {"error": err["detail"] ?? "Request failed (${response.statusCode})"};
          } catch (_) {
            return {"error": "Server error (${response.statusCode})"};
          }
        }
      } catch (e) {
        if (attempt == 0) {
          final discovered = await autoDiscoverServer();
          if (discovered != null) {
            continue;
          }
        }
        return {"error": "Cannot connect to server. Please check backend connection."};
      }
    }
    return {"error": "Cannot connect to server. Please check backend connection."};
  }

  static Future<Map<String, dynamic>?> resetPassword({
    required String emailOrUsername,
    required String resetCode,
    required String newPassword,
  }) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/reset-password'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'email_or_username': emailOrUsername,
            'reset_code': resetCode,
            'new_password': newPassword,
          }),
        ).timeout(defaultTimeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          try {
            final err = jsonDecode(response.body);
            return {"error": err["detail"] ?? "Reset failed (${response.statusCode})"};
          } catch (_) {
            return {"error": "Server error (${response.statusCode})"};
          }
        }
      } catch (e) {
        if (attempt == 0) {
          final discovered = await autoDiscoverServer();
          if (discovered != null) {
            continue;
          }
        }
        return {"error": "Cannot connect to server. Please check backend connection."};
      }
    }
    return {"error": "Cannot connect to server. Please check backend connection."};
  }

  // =========================
  // TWO-FACTOR AUTHENTICATION (2FA)
  // =========================
  static Future<Map<String, dynamic>?> setup2FA({String? token}) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final headers = await _authHeaders(token: token);
        final response = await http.post(
          Uri.parse('$baseUrl/2fa/setup'),
          headers: headers,
        ).timeout(defaultTimeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          try {
            final err = jsonDecode(response.body);
            return {"error": err["detail"] ?? "Failed to setup 2FA"};
          } catch (_) {
            return {"error": "Server error (${response.statusCode})"};
          }
        }
      } catch (e) {
        if (attempt == 0) {
          final discovered = await autoDiscoverServer();
          if (discovered != null) continue;
        }
        return {"error": "Cannot connect to server."};
      }
    }
    return {"error": "Cannot connect to server."};
  }

  static Future<Map<String, dynamic>?> send2FAEmailCode({
    String? tempToken,
    String? token,
  }) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final headers = await _authHeaders(token: token);
        final response = await http.post(
          Uri.parse('$baseUrl/2fa/email/send-code'),
          headers: headers,
          body: jsonEncode({
            if (tempToken != null) 'temp_token': tempToken,
          }),
        ).timeout(defaultTimeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          try {
            final err = jsonDecode(response.body);
            return {"error": err["detail"] ?? "Failed to send email verification code"};
          } catch (_) {
            return {"error": "Server error (${response.statusCode})"};
          }
        }
      } catch (e) {
        if (attempt == 0) {
          final discovered = await autoDiscoverServer();
          if (discovered != null) continue;
        }
        return {"error": "Cannot connect to server."};
      }
    }
    return {"error": "Cannot connect to server."};
  }

  static Future<Map<String, dynamic>?> enable2FA({
    required String code,
    required List<String> backupCodes,
    String method = "totp",
    String? secret,
    String? token,
  }) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final headers = await _authHeaders(token: token);
        final response = await http.post(
          Uri.parse('$baseUrl/2fa/enable'),
          headers: headers,
          body: jsonEncode({
            'method': method,
            'code': code,
            if (secret != null) 'secret': secret,
            'backup_codes': backupCodes,
          }),
        ).timeout(defaultTimeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          try {
            final err = jsonDecode(response.body);
            return {"error": err["detail"] ?? "Failed to enable 2FA"};
          } catch (_) {
            return {"error": "Server error (${response.statusCode})"};
          }
        }
      } catch (e) {
        if (attempt == 0) {
          final discovered = await autoDiscoverServer();
          if (discovered != null) continue;
        }
        return {"error": "Cannot connect to server."};
      }
    }
    return {"error": "Cannot connect to server."};
  }

  static Future<Map<String, dynamic>?> disable2FA({
    String? password,
    String? code,
    String? token,
  }) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final headers = await _authHeaders(token: token);
        final response = await http.post(
          Uri.parse('$baseUrl/2fa/disable'),
          headers: headers,
          body: jsonEncode({
            if (password != null) 'password': password,
            if (code != null) 'code': code,
          }),
        ).timeout(defaultTimeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          try {
            final err = jsonDecode(response.body);
            return {"error": err["detail"] ?? "Failed to disable 2FA"};
          } catch (_) {
            return {"error": "Server error (${response.statusCode})"};
          }
        }
      } catch (e) {
        if (attempt == 0) {
          final discovered = await autoDiscoverServer();
          if (discovered != null) continue;
        }
        return {"error": "Cannot connect to server."};
      }
    }
    return {"error": "Cannot connect to server."};
  }

  static Future<Map<String, dynamic>?> verify2FALogin({
    required String tempToken,
    required String code,
  }) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/2fa/verify-login'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'temp_token': tempToken,
            'code': code,
          }),
        ).timeout(defaultTimeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          try {
            final err = jsonDecode(response.body);
            return {"error": err["detail"] ?? "Invalid 2FA code (${response.statusCode})"};
          } catch (_) {
            return {"error": "Server error (${response.statusCode})"};
          }
        }
      } catch (e) {
        if (attempt == 0) {
          final discovered = await autoDiscoverServer();
          if (discovered != null) continue;
        }
        return {"error": "Cannot connect to server."};
      }
    }
    return {"error": "Cannot connect to server."};
  }

  static Future<Map<String, dynamic>?> get2FAStatus({String? token}) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.get(
        Uri.parse('$baseUrl/2fa/status'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // =========================
  // GENERATE PIN
  // =========================
  static Future<Map<String, dynamic>?> generatePin(
    int userId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.get(
        Uri.parse('$baseUrl/generate-pin/$userId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // =========================
  // CONNECT BY PIN
  // =========================
  static Future<Map<String, dynamic>?> connectByPin(
    int userId,
    String pin, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.post(
        Uri.parse('$baseUrl/connect-by-pin'),
        headers: headers,
        body: jsonEncode({
          'user_id': userId,
          'pin_code': pin,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // =========================
  // GET CURRENT USER
  // =========================
  static Future<Map<String, dynamic>?> getMe(
    String token,
  ) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.get(
        Uri.parse('$baseUrl/me'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getPairStatus(
    int userId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.get(
        Uri.parse('$baseUrl/pair-status/$userId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // =========================
  // E2EE PUBLIC KEYS
  // =========================
  static Future<bool> uploadPublicKey(String publicKey, {String? token}) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.post(
        Uri.parse('$baseUrl/keys/public'),
        headers: headers,
        body: jsonEncode({'public_key': publicKey}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> fetchPublicKey(int userId, {String? token}) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.get(
        Uri.parse('$baseUrl/keys/$userId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['public_key'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> sendMessage(
    int senderId,
    int receiverId,
    String content, {
    String? nonce,
    bool isEncrypted = false,
    List<int> mediaIds = const [],
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.post(
        Uri.parse('$baseUrl/send-message'),
        headers: headers,
        body: jsonEncode({
          'sender_id': senderId,
          'receiver_id': receiverId,
          'content': content,
          'nonce': nonce,
          'is_encrypted': isEncrypted,
          'media_ids': mediaIds,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // =========================
  // MEDIA UPLOAD & GALLERY
  // =========================
  static Future<List<Map<String, dynamic>>?> uploadMediaFiles(
    int receiverId,
    List<File> files,
    String token, {
    bool isEncrypted = false,
    bool isViewOnce = false,
    String? encryptedMediaKey,
    String? encryptionNonce,
    void Function(double progress)? onProgress,
  }) async {
    try {
      var uri = Uri.parse("$baseUrl/media/upload");
      var request = http.MultipartRequest('POST', uri);

      final authToken = token.isNotEmpty ? token : (await Session.getToken() ?? '');
      if (authToken.isEmpty) {
        return null;
      }
      request.headers['Authorization'] = 'Bearer $authToken';
      request.fields['receiver_id'] = receiverId.toString();
      request.fields['is_encrypted'] = isEncrypted ? 'true' : 'false';
      request.fields['is_view_once'] = isViewOnce ? 'true' : 'false';
      if (encryptedMediaKey != null) request.fields['encrypted_media_key'] = encryptedMediaKey;
      if (encryptionNonce != null) request.fields['encryption_nonce'] = encryptionNonce;

      for (var file in files) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'files',
            file.path,
          ),
        );
      }

      final streamedResponse = await request.send();

      if (streamedResponse.statusCode == 200) {
        final responseBody = await streamedResponse.stream.bytesToString();
        final List<dynamic> list = jsonDecode(responseBody);
        return list.cast<Map<String, dynamic>>();
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  static String getMediaFileUrl(int mediaId) {
    return "$baseUrl/media/$mediaId/file";
  }

  static String getMediaThumbnailUrl(int mediaId) {
    return "$baseUrl/media/$mediaId/thumbnail";
  }

  static Future<Uint8List?> fetchAuthenticatedBytes(String url, String token) async {
    try {
      final authToken = token.isNotEmpty ? token : (await Session.getToken() ?? '');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $authToken',
        },
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<File?> downloadAuthenticatedFile(String url, String token, String filename) async {
    try {
      final bytes = await fetchAuthenticatedBytes(url, token);
      if (bytes != null) {
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/$filename');
        await tempFile.writeAsBytes(bytes);
        return tempFile;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<dynamic>> getPairMediaGallery(
    int partnerId,
    String token, {
    String? mediaType,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      String url = "$baseUrl/media/pair/$partnerId?limit=$limit&offset=$offset";
      if (mediaType != null && mediaType.isNotEmpty) {
        url += "&media_type=$mediaType";
      }

      final authToken = token.isNotEmpty ? token : (await Session.getToken() ?? '');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $authToken',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> deleteMediaItem(int mediaId, String token) async {
    try {
      final authToken = token.isNotEmpty ? token : (await Session.getToken() ?? '');
      final response = await http.delete(
        Uri.parse("$baseUrl/media/$mediaId"),
        headers: {
          'Authorization': 'Bearer $authToken',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> getMessages(
    int user1,
    int user2, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.get(
        Uri.parse('$baseUrl/messages/$user1/$user2'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> deleteMessage(
    int messageId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.delete(
        Uri.parse('$baseUrl/messages/$messageId'),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> clearConversation(
    int partnerId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.delete(
        Uri.parse('$baseUrl/messages/conversation/$partnerId'),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> clearCallHistory(
    int partnerId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.delete(
        Uri.parse('$baseUrl/call/history/$partnerId'),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> editMessage(
    int messageId,
    String newContent, {
    String? nonce,
    bool isEncrypted = false,
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.put(
        Uri.parse('$baseUrl/messages/$messageId'),
        headers: headers,
        body: jsonEncode({
          'content': newContent,
          'nonce': nonce,
          'is_encrypted': isEncrypted,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> sendHeartbeat({String? token}) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.post(
        Uri.parse("$baseUrl/heartbeat"),
        headers: headers,
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getOnlineStatus(
    int userId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.get(
        Uri.parse("$baseUrl/user/$userId/status"),
        headers: headers,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getProfile(
    int userId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token, json: false);
      final response = await http.get(
        Uri.parse("$baseUrl/profile/$userId"),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> updateProfile(
    int userId,
    String username,
    String bio,
    String birthday, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.put(
        Uri.parse("$baseUrl/profile/$userId"),
        headers: headers,
        body: jsonEncode({
          "username": username,
          "bio": bio,
          "birthday": birthday,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> uploadAvatar(
    int userId,
    File image, {
    String? token,
  }) async {
    try {
      final authToken = (token != null && token.isNotEmpty) ? token : (await Session.getToken() ?? '');
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$baseUrl/profile/avatar/$userId"),
      );
      if (authToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }

      request.files.add(
        await http.MultipartFile.fromPath(
          "file",
          image.path,
        ),
      );

      final response = await request.send();

      if (response.statusCode == 200) {
        final body = await response.stream.bytesToString();
        return jsonDecode(body)["avatar_url"];
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> changePassword(
    int userId,
    String currentPassword,
    String newPassword, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.put(
        Uri.parse("$baseUrl/change-password/$userId"),
        headers: headers,
        body: jsonEncode({
          "current_password": currentPassword,
          "new_password": newPassword,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ===========================================================================
  // DIARY & MEMORY PHOTO GALLERY API
  // ===========================================================================

  static Future<List<dynamic>> getPairMemories(
    int partnerId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.get(
        Uri.parse("$baseUrl/memories/pair/$partnerId"),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> createDiaryMemory({
    required int partnerId,
    required String entryDate,
    required String content,
    String? moodEmoji,
    File? photo,
    String? token,
  }) async {
    try {
      final authToken = token ?? (await Session.getToken() ?? '');
      var uri = Uri.parse("$baseUrl/memories/create");
      var request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $authToken';
      request.fields['partner_id'] = partnerId.toString();
      request.fields['entry_date'] = entryDate;
      request.fields['content'] = content;
      if (moodEmoji != null && moodEmoji.isNotEmpty) {
        request.fields['mood_emoji'] = moodEmoji;
      }

      if (photo != null && await photo.exists()) {
        request.files.add(
          await http.MultipartFile.fromPath('photo', photo.path),
        );
      }

      final streamed = await request.send();
      if (streamed.statusCode == 200) {
        final body = await streamed.stream.bytesToString();
        return jsonDecode(body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> deleteDiaryMemory(
    int memoryId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.delete(
        Uri.parse("$baseUrl/memories/$memoryId"),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // =========================
  // VOICE & VIDEO CALLING
  // =========================
  static Future<Map<String, dynamic>?> initiateCall(
    int receiverId, {
    String callType = 'voice',
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.post(
        Uri.parse('$baseUrl/call/initiate'),
        headers: headers,
        body: jsonEncode({
          'receiver_id': receiverId,
          'call_type': callType,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> respondToCall(
    int callId,
    String action, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.post(
        Uri.parse('$baseUrl/call/respond'),
        headers: headers,
        body: jsonEncode({
          'call_id': callId,
          'action': action,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> endCall(
    int callId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.post(
        Uri.parse('$baseUrl/call/end'),
        headers: headers,
        body: jsonEncode({
          'call_id': callId,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getActiveCall(
    int userId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.get(
        Uri.parse('$baseUrl/call/active/$userId'),
        headers: headers,
      );
      if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<dynamic>> getCallHistory(
    int partnerId, {
    String? token,
  }) async {
    try {
      final headers = await _authHeaders(token: token);
      final response = await http.get(
        Uri.parse('$baseUrl/call/history/$partnerId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}