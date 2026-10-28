import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twoofus_flutter/models/message.dart';
import 'package:twoofus_flutter/models/media.dart';
import 'package:twoofus_flutter/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('LocalDatabaseService Tests', () {
    setUp(() async {
      await LocalDatabaseService.instance.clearAll();
    });

    test('Saves and retrieves cached messages in chronological order', () async {
      final now = DateTime.now();
      final msg1 = Message(
        id: 101,
        senderId: 1,
        receiverId: 2,
        content: 'Hello offline world',
        createdAt: now.subtract(const Duration(minutes: 5)),
        isEncrypted: true,
      );
      final msg2 = Message(
        id: 102,
        senderId: 2,
        receiverId: 1,
        content: 'Hi! Everything works offline',
        createdAt: now,
        isEncrypted: true,
      );

      await LocalDatabaseService.instance.saveMessages([msg2, msg1]);

      final cached = await LocalDatabaseService.instance.getCachedMessages(
        myId: 1,
        partnerId: 2,
      );

      expect(cached.length, equals(2));
      expect(cached[0].id, equals(101));
      expect(cached[0].content, equals('Hello offline world'));
      expect(cached[1].id, equals(102));
      expect(cached[1].content, equals('Hi! Everything works offline'));
    });

    test('Preserves media attachment metadata in SQLite', () async {
      final now = DateTime.now();
      final media = MediaItem(
        id: 55,
        senderId: 1,
        receiverId: 2,
        originalFilename: 'sunset.jpg',
        storedFilename: 'enc_sunset.enc',
        mediaType: 'image',
        mimeType: 'image/jpeg',
        fileSize: 10240,
        storagePath: 'media/enc_sunset.enc',
      );

      final msg = Message(
        id: 200,
        senderId: 1,
        receiverId: 2,
        content: 'Look at this photo',
        createdAt: now,
        mediaAttachments: [media],
      );

      await LocalDatabaseService.instance.saveMessages([msg]);

      final cached = await LocalDatabaseService.instance.getCachedMessages(
        myId: 1,
        partnerId: 2,
      );

      expect(cached.length, equals(1));
      expect(cached[0].mediaAttachments.length, equals(1));
      expect(cached[0].mediaAttachments[0].originalFilename, equals('sunset.jpg'));
      expect(cached[0].mediaAttachments[0].mediaType, equals('image'));
    });

    test('Deletes single message from SQLite', () async {
      final msg = Message(
        id: 300,
        senderId: 1,
        receiverId: 2,
        content: 'To be deleted',
        createdAt: DateTime.now(),
      );

      await LocalDatabaseService.instance.saveMessages([msg]);
      var cached = await LocalDatabaseService.instance.getCachedMessages(
        myId: 1,
        partnerId: 2,
      );
      expect(cached.length, equals(1));

      final deletedCount = await LocalDatabaseService.instance.deleteMessage(300);
      expect(deletedCount, equals(1));

      cached = await LocalDatabaseService.instance.getCachedMessages(
        myId: 1,
        partnerId: 2,
      );
      expect(cached.isEmpty, isTrue);
    });

    test('Saves, retrieves, and deletes call logs in SQLite', () async {
      final log = {
        'id': 10,
        'caller_id': 1,
        'receiver_id': 2,
        'call_type': 'video',
        'status': 'completed',
        'duration_seconds': 145,
        'created_at': DateTime.now().toIso8601String(),
      };

      await LocalDatabaseService.instance.saveCallLogs([log]);

      var logs = await LocalDatabaseService.instance.getCachedCallLogs(
        myId: 1,
        partnerId: 2,
      );
      expect(logs.length, equals(1));
      expect(logs[0]['call_type'], equals('video'));
      expect(logs[0]['duration_seconds'], equals(145));

      final deleted = await LocalDatabaseService.instance.deleteCallLog(10);
      expect(deleted, equals(1));

      logs = await LocalDatabaseService.instance.getCachedCallLogs(
        myId: 1,
        partnerId: 2,
      );
      expect(logs.isEmpty, isTrue);
    });
  });
}

