import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoofus_flutter/models/call_session.dart';
import 'package:twoofus_flutter/services/call_notification_service.dart';
import 'package:twoofus_flutter/services/call_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

    test('CallService.endCall resets audio and speaker state to unmuted and speaker active', () async {
      CallService.isMutedNotifier.value = true;
      CallService.isSpeakerNotifier.value = false;
      CallService.isVideoEnabledNotifier.value = true;
      CallService.isFrontCameraNotifier.value = false;

      await CallService.endCall(101);

      expect(CallService.isMutedNotifier.value, false);
      expect(CallService.isSpeakerNotifier.value, true);
      expect(CallService.isVideoEnabledNotifier.value, false);
      expect(CallService.isFrontCameraNotifier.value, true);
    });

    test('Opus SDP formatting ensures useinbandfec and usedtx without duplicate attributes', () {
      const sampleSdp = "v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=rtpmap:111 opus/48000/2\r\na=fmtp:111 minptime=10\r\n";

      final lines = sampleSdp.split(RegExp(r'\r\n|\n'));
      String? opusPt;
      for (final line in lines) {
        final match = RegExp(r'^a=rtpmap:(\d+)\s+opus/48000/2').firstMatch(line.trim());
        if (match != null) {
          opusPt = match.group(1);
          break;
        }
      }
      expect(opusPt, '111');

      final updatedLines = <String>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('a=fmtp:$opusPt')) {
          var fmtp = trimmed;
          if (!fmtp.contains('useinbandfec=')) fmtp += ';useinbandfec=1';
          if (!fmtp.contains('usedtx=')) fmtp += ';usedtx=1';
          updatedLines.add(fmtp);
        } else {
          updatedLines.add(trimmed);
        }
      }

      final result = updatedLines.join('\r\n');
      expect(result.contains('a=fmtp:111 minptime=10;useinbandfec=1;usedtx=1'), true);
      expect('minptime'.allMatches(result).length, 1);
    });

    test('Candidate type regex parses host, srflx, and relay types accurately', () {
      const hostCandidate = "candidate:1 1 UDP 2122260223 192.168.1.100 50000 typ host generation 0";
      const srflxCandidate = "candidate:2 1 UDP 1686052607 203.0.113.195 50000 typ srflx raddr 192.168.1.100 rport 50000 generation 0";
      const relayCandidate = "candidate:3 1 UDP 41885695 198.51.100.1 50000 typ relay raddr 203.0.113.195 rport 50000 generation 0";

      String parseType(String c) {
        final match = RegExp(r'typ\s+([a-zA-Z0-9]+)').firstMatch(c);
        return match != null ? match.group(1)! : 'unknown';
      }

      expect(parseType(hostCandidate), 'host');
      expect(parseType(srflxCandidate), 'srflx');
      expect(parseType(relayCandidate), 'relay');
      expect(parseType('invalid_candidate'), 'unknown');
    });

    test('Single-use ticket WebSocket URI formation is formatted accurately', () {
      const baseWsUrl = 'ws://example.com/ws/call';
      const sampleTicket = 'call_ticket_abcdef123456';
      final uriWithTicket = Uri.parse('$baseWsUrl?ticket=$sampleTicket');
      expect(uriWithTicket.queryParameters['ticket'], sampleTicket);
      expect(uriWithTicket.queryParameters.containsKey('token'), false);

      const sampleToken = 'jwt.test.token';
      final uriWithToken = Uri.parse('$baseWsUrl?token=$sampleToken');
      expect(uriWithToken.queryParameters['token'], sampleToken);
      expect(uriWithToken.queryParameters.containsKey('ticket'), false);
    });

    test('FCM incoming_call data message parses call_id, caller_name, call_type correctly', () {
      final fcmDataPayload = {
        'type': 'incoming_call',
        'call_id': '456',
        'caller_name': 'Bob',
        'call_type': 'video',
      };

      expect(fcmDataPayload['type'], 'incoming_call');
      final callId = int.tryParse(fcmDataPayload['call_id'] ?? '') ?? 0;
      final callerName = fcmDataPayload['caller_name'] ?? 'Partner';
      final callType = fcmDataPayload['call_type'] ?? 'voice';

      expect(callId, 456);
      expect(callerName, 'Bob');
      expect(callType, 'video');
    });

    test('Cross-isolate persistent deduplication via SharedPreferences reload()', () async {
      SharedPreferences.setMockInitialValues({});
      const testCallId = 8842;

      // Simulate two separate isolates obtaining SharedPreferences instances
      final isolate1Prefs = await SharedPreferences.getInstance();
      final isolate2Prefs = await SharedPreferences.getInstance();

      // Initial check should be false
      expect(await CallNotificationService.isCallPersistentlyHandled(testCallId), isFalse);

      // Isolate 1 handles the call and marks it in persistent storage
      await isolate1Prefs.setStringList('fcm_handled_call_ids', [testCallId.toString()]);

      // Isolate 2 checks via isCallPersistentlyHandled, which reloads from persistent storage
      expect(await CallNotificationService.isCallPersistentlyHandled(testCallId), isTrue);

      // Verify isolate 2 reloads and reflects the updated handled list
      await isolate2Prefs.reload();
      final list = isolate2Prefs.getStringList('fcm_handled_call_ids');
      expect(list, isNotNull);
      expect(list, contains(testCallId.toString()));

      // Duplicate mark does not add duplicate entries
      await CallNotificationService.markCallPersistentlyHandled(testCallId);
      await isolate2Prefs.reload();
      final listAfter = isolate2Prefs.getStringList('fcm_handled_call_ids');
      expect(listAfter!.where((id) => id == testCallId.toString()).length, 1);
    });
  });
}
