class CallSessionModel {
  final int id;
  final int callerId;
  final int receiverId;
  final String callType; // "voice" | "video"
  final String status;   // "ringing" | "ongoing" | "ended" | "rejected" | "missed"
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final DateTime createdAt;

  CallSessionModel({
    required this.id,
    required this.callerId,
    required this.receiverId,
    required this.callType,
    required this.status,
    this.startedAt,
    this.endedAt,
    this.durationSeconds = 0,
    required this.createdAt,
  });

  factory CallSessionModel.fromJson(Map<String, dynamic> json) {
    return CallSessionModel(
      id: json['id'] as int,
      callerId: json['caller_id'] as int,
      receiverId: json['receiver_id'] as int,
      callType: (json['call_type'] as String?) ?? 'voice',
      status: (json['status'] as String?) ?? 'ringing',
      startedAt: json['started_at'] != null ? DateTime.tryParse(json['started_at']) : null,
      endedAt: json['ended_at'] != null ? DateTime.tryParse(json['ended_at']) : null,
      durationSeconds: (json['duration_seconds'] as int?) ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'caller_id': callerId,
      'receiver_id': receiverId,
      'call_type': callType,
      'status': status,
      'started_at': startedAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
