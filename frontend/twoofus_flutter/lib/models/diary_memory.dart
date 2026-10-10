import '../services/api_service.dart';
import '../utils/date_time_utils.dart';

class DiaryMemoryItem {
  final int id;
  final int senderId;
  final int receiverId;
  final String entryDate; // "YYYY-MM-DD"
  final String content;
  final String? moodEmoji;
  final String? imageUrl;
  final bool isEncrypted;
  final String? contentNonce;
  final String? photoNonce;
  final DateTime? createdAt;

  DiaryMemoryItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.entryDate,
    required this.content,
    this.moodEmoji,
    this.imageUrl,
    this.isEncrypted = false,
    this.contentNonce,
    this.photoNonce,
    this.createdAt,
  });

  factory DiaryMemoryItem.fromJson(Map<String, dynamic> json) {
    return DiaryMemoryItem(
      id: json['id'] ?? 0,
      senderId: json['sender_id'] ?? 0,
      receiverId: json['receiver_id'] ?? 0,
      entryDate: json['entry_date'] ?? '',
      content: json['content'] ?? '',
      moodEmoji: json['mood_emoji'],
      imageUrl: json['image_url'],
      isEncrypted: json['is_encrypted'] == true,
      contentNonce: json['content_nonce'],
      photoNonce: json['photo_nonce'],
      createdAt: json['created_at'] != null ? DateTimeUtils.parseToLocal(json['created_at']) : null,
    );
  }

  DiaryMemoryItem copyWith({
    int? id,
    int? senderId,
    int? receiverId,
    String? entryDate,
    String? content,
    String? moodEmoji,
    String? imageUrl,
    bool? isEncrypted,
    String? contentNonce,
    String? photoNonce,
    DateTime? createdAt,
  }) {
    return DiaryMemoryItem(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      entryDate: entryDate ?? this.entryDate,
      content: content ?? this.content,
      moodEmoji: moodEmoji ?? this.moodEmoji,
      imageUrl: imageUrl ?? this.imageUrl,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      contentNonce: contentNonce ?? this.contentNonce,
      photoNonce: photoNonce ?? this.photoNonce,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get hasPhoto => imageUrl != null && imageUrl!.isNotEmpty;

  String? get fullImageUrl {
    if (imageUrl == null || imageUrl!.isEmpty) return null;
    if (imageUrl!.startsWith('http')) return imageUrl;
    final cleanPath = imageUrl!.startsWith('/') ? imageUrl!.substring(1) : imageUrl!;
    return "${ApiService.baseUrl}/$cleanPath";
  }

  DateTime? get parsedDate {
    try {
      final parts = entryDate.split('-');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    } catch (_) {}
    return null;
  }
}
