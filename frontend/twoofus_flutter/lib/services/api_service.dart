import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/session.dart';

class ApiService {
  static String get baseUrl {
    if (kIsWeb) {
      return "http://localhost:8000";
    } else if (Platform.isAndroid) {
      return "http://10.0.2.2:8000";
    } else {
      return "http://127.0.0.1:8000";
    }
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

  // =========================
  // LOGIN
  // =========================
  static Future<Map<String, dynamic>?> login(
    String email,
    String password,
  ) async {
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
  // REGISTER
  // =========================
  static Future<Map<String, dynamic>?> register(
    String email,
    String username,
    String password,
  ) async {
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
}