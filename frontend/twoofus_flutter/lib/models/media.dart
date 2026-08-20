class MediaItem {
  final int id;
  final int? messageId;
  final int senderId;
  final int receiverId;
  final String originalFilename;
  final String storedFilename;
  final String mediaType; // "image", "video", "file"
  final String mimeType;
  final int fileSize;
  final String storagePath;
  final String? thumbnailPath;
  final DateTime? createdAt;

  final bool isEncrypted;
  final bool isViewOnce;
  final bool isExpired;
  final DateTime? viewedAt;
  final String? encryptedMediaKey;
  final String? encryptionNonce;

  MediaItem({
    required this.id,
    this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.originalFilename,
    required this.storedFilename,
    required this.mediaType,
    required this.mimeType,
    required this.fileSize,
    required this.storagePath,
    this.thumbnailPath,
    this.createdAt,
    this.isEncrypted = false,
    this.isViewOnce = false,
    this.isExpired = false,
    this.viewedAt,
    this.encryptedMediaKey,
    this.encryptionNonce,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] ?? 0,
      messageId: json['message_id'],
      senderId: json['sender_id'] ?? 0,
      receiverId: json['receiver_id'] ?? 0,
      originalFilename: json['original_filename'] ?? 'attachment',
      storedFilename: json['stored_filename'] ?? '',
      mediaType: json['media_type'] ?? 'file',
      mimeType: json['mime_type'] ?? 'application/octet-stream',
      fileSize: json['file_size'] ?? 0,
      storagePath: json['storage_path'] ?? '',
      thumbnailPath: json['thumbnail_path'],
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      isEncrypted: json['is_encrypted'] ?? false,
      isViewOnce: json['is_view_once'] ?? false,
      isExpired: json['is_expired'] ?? false,
      viewedAt: json['viewed_at'] != null ? DateTime.tryParse(json['viewed_at'].toString()) : null,
      encryptedMediaKey: json['encrypted_media_key'],
      encryptionNonce: json['encryption_nonce'],
    );
  }

  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
  bool get isFile => mediaType == 'file';

  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
