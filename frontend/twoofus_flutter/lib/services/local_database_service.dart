import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/media.dart';
import '../models/message.dart';
import '../utils/date_time_utils.dart';

class LocalDatabaseService {
  LocalDatabaseService._();
  static final LocalDatabaseService instance = LocalDatabaseService._();

  static Database? _database;
  static const String _dbName = 'twoofus_local_cache.db';
  static const int _dbVersion = 1;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY,
            sender_id INTEGER NOT NULL,
            receiver_id INTEGER NOT NULL,
            content TEXT NOT NULL,
            nonce TEXT,
            is_encrypted INTEGER NOT NULL DEFAULT 0,
            is_edited INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            media_json TEXT
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_messages_participants_created 
          ON messages(sender_id, receiver_id, created_at)
        ''');

        await db.execute('''
          CREATE TABLE call_logs (
            id INTEGER PRIMARY KEY,
            caller_id INTEGER NOT NULL,
            receiver_id INTEGER NOT NULL,
            call_type TEXT NOT NULL,
            status TEXT NOT NULL,
            duration_seconds INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_call_logs_participants 
          ON call_logs(caller_id, receiver_id, created_at)
        ''');
      },
    );
  }

  /// Upsert a list of messages into SQLite
  Future<void> saveMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    try {
      final db = await database;
      final batch = db.batch();

      for (final m in messages) {
        final mediaJson = m.mediaAttachments.isNotEmpty
            ? jsonEncode(m.mediaAttachments.map((e) => e.toJson()).toList())
            : null;

        batch.insert(
          'messages',
          {
            'id': m.id,
            'sender_id': m.senderId,
            'receiver_id': m.receiverId,
            'content': m.content,
            'nonce': m.nonce,
            'is_encrypted': m.isEncrypted ? 1 : 0,
            'is_edited': m.isEdited ? 1 : 0,
            'created_at': m.createdAt.toIso8601String(),
            'media_json': mediaJson,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    } catch (_) {}
  }

  /// Upsert a single message
  Future<void> saveMessage(Message message) async {
    await saveMessages([message]);
  }

  /// Retrieve all cached messages for a conversation
  Future<List<Message>> getCachedMessages({
    required int myId,
    required int partnerId,
  }) async {
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT * FROM messages
        WHERE (sender_id = ? AND receiver_id = ?)
           OR (sender_id = ? AND receiver_id = ?)
        ORDER BY created_at ASC
      ''', [myId, partnerId, partnerId, myId]);

      return rows.map((row) {
        List<MediaItem> mediaList = [];
        final mediaJson = row['media_json'] as String?;
        if (mediaJson != null && mediaJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(mediaJson) as List<dynamic>;
            mediaList = decoded
                .map((m) => MediaItem.fromJson(m as Map<String, dynamic>))
                .toList();
          } catch (_) {}
        }

        return Message(
          id: row['id'] as int,
          senderId: row['sender_id'] as int,
          receiverId: row['receiver_id'] as int,
          content: row['content'] as String,
          nonce: row['nonce'] as String?,
          isEncrypted: (row['is_encrypted'] as int? ?? 0) == 1,
          isEdited: (row['is_edited'] as int? ?? 0) == 1,
          createdAt: DateTimeUtils.parseToLocal(row['created_at'] as String),
          mediaAttachments: mediaList,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Delete a single message from the local database
  Future<int> deleteMessage(int messageId) async {
    try {
      final db = await database;
      return await db.delete(
        'messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (_) {
      return 0;
    }
  }

  /// Upsert call logs
  Future<void> saveCallLogs(List<dynamic> logs) async {
    if (logs.isEmpty) return;
    try {
      final db = await database;
      final batch = db.batch();

      for (final l in logs) {
        if (l is! Map) continue;
        final id = l['id'];
        if (id == null) continue;

        batch.insert(
          'call_logs',
          {
            'id': id,
            'caller_id': l['caller_id'] ?? 0,
            'receiver_id': l['receiver_id'] ?? 0,
            'call_type': l['call_type'] ?? 'audio',
            'status': l['status'] ?? 'completed',
            'duration_seconds': l['duration_seconds'] ?? 0,
            'created_at': l['created_at']?.toString() ?? DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    } catch (_) {}
  }

  /// Retrieve cached call logs for a conversation
  Future<List<Map<String, dynamic>>> getCachedCallLogs({
    required int myId,
    required int partnerId,
  }) async {
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT * FROM call_logs
        WHERE (caller_id = ? AND receiver_id = ?)
           OR (caller_id = ? AND receiver_id = ?)
        ORDER BY created_at ASC
      ''', [myId, partnerId, partnerId, myId]);

      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Delete a call log by its call ID
  Future<int> deleteCallLog(int callId) async {
    try {
      final db = await database;
      return await db.delete(
        'call_logs',
        where: 'id = ?',
        whereArgs: [callId],
      );
    } catch (_) {
      return 0;
    }
  }

  /// Wipe all local SQLite cached records (e.g., on full account reset)
  Future<void> clearAll() async {
    try {
      final db = await database;
      await db.delete('messages');
      await db.delete('call_logs');
    } catch (_) {}
  }
}

