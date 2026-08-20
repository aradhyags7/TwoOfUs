import 'media.dart';

class Message {
  final int id;

  final int senderId;
  final int receiverId;

  final String content;
  final String? nonce;
  final bool isEncrypted;
  final bool isEdited;

  final DateTime createdAt;
  final List<MediaItem> mediaAttachments;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.nonce,
    this.isEncrypted = false,
    this.isEdited = false,
    required this.createdAt,
    this.mediaAttachments = const [],
  });

  factory Message.fromJson(
    Map<String, dynamic> json,
  ) {
    List<MediaItem> mediaList = [];
    if (json["media"] != null && json["media"] is List) {
      mediaList = (json["media"] as List)
          .map((m) => MediaItem.fromJson(m))
          .toList();
    }

    return Message(
      id: json["id"],

      senderId: json["sender_id"],
      receiverId: json["receiver_id"],

      content: json["content"],
      nonce: json["nonce"],
      isEncrypted: json["is_encrypted"] ?? false,
      isEdited: json["is_edited"] ?? false,

      createdAt: DateTime.parse(
        json["created_at"],
      ),
      mediaAttachments: mediaList,
    );
  }
}