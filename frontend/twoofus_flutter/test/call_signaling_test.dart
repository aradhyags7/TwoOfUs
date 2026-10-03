import 'package:flutter_test/flutter_test.dart';
import 'package:twoofus_flutter/models/call_session.dart';
import 'package:twoofus_flutter/services/call_service.dart';

void main() {
  group('CallSessionModel & Signaling Parsing Tests', () {
    test('Correctly parses incoming_call WebSocket signaling message', () {
      final signalingMsg = {
        'type': 'incoming_call',
        'call_id': 42,
        'caller_id': 7,
        'caller_name': 'Alice',
        'call_type': 'video',
        'created_at': '2026-10-03T14:30:00.000Z',
      };

      final session = CallSessionModel.fromSignaling(signalingMsg, 99);
      expect(session.id, 42);
      expect(session.callerId, 7);
      expect(session.receiverId, 99);
      expect(session.callType, 'video');
      expect(session.status, 'ringing');
      expect(session.durationSeconds, 0);
    });

    test('Correctly serializes and deserializes CallSessionModel JSON', () {
      final session = CallSessionModel(
        id: 101,
        callerId: 1,
        receiverId: 2,
        callType: 'voice',
        status: 'ongoing',
        createdAt: DateTime.utc(2026, 10, 3, 14, 0, 0),
      );

      final json = session.toJson();
      expect(json['id'], 101);
      expect(json['caller_id'], 1);
      expect(json['receiver_id'], 2);
      expect(json['status'], 'ongoing');

      final deserialized = CallSessionModel.fromJson(json);
      expect(deserialized.id, 101);
      expect(deserialized.callerId, 1);
      expect(deserialized.callType, 'voice');
    });

    test('CallService audio and video state notifiers toggle accurately', () {
      CallService.isMutedNotifier.value = false;
      CallService.toggleMute();
      expect(CallService.isMutedNotifier.value, true);

      CallService.isSpeakerNotifier.value = false;
      CallService.toggleSpeaker();
      expect(CallService.isSpeakerNotifier.value, true);

      CallService.isVideoEnabledNotifier.value = true;
      CallService.toggleVideo();
      expect(CallService.isVideoEnabledNotifier.value, false);

      CallService.isFrontCameraNotifier.value = true;
      CallService.flipCamera();
      expect(CallService.isFrontCameraNotifier.value, false);
    });
  });
}
