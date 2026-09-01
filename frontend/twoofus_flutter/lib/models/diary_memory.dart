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
  final DateTime? createdAt;

  DiaryMemoryItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.entryDate,
    required this.content,
    this.moodEmoji,
    this.imageUrl,
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
      createdAt: json['created_at'] != null ? DateTimeUtils.parseToLocal(json['created_at']) : null,
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
