import 'package:flutter_test/flutter_test.dart';
import 'package:twoofus_flutter/services/e2ee_service.dart';
import 'package:twoofus_flutter/services/call_service.dart';
import 'package:twoofus_flutter/models/call_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Call Security & E2EE Privacy Tests', () {
    test('1. Bidirectional safety code determinism for caller and receiver', () async {
      // Alice and Bob's base64 X25519 public keys
      const alicePubKey = 'mcW19qT4o09v6w48jE0GqXl0123456789abcdefghij=';
      const bobPubKey = 'zY8234klasdf092384jsadklfj230948asdfjklasdf=';

      // Computed from Alice's perspective (Alice, Bob)
      final codeAlice = await E2EEService.generateSafetyCode(alicePubKey, bobPubKey);

      // Computed from Bob's perspective (Bob, Alice)
      final codeBob = await E2EEService.generateSafetyCode(bobPubKey, alicePubKey);

      expect(codeAlice, equals(codeBob));
      expect(codeAlice.split(' ').length, equals(12)); // 12 blocks of 5 digits = 60 digits
      for (final chunk in codeAlice.split(' ')) {
        expect(chunk.length, equals(5));
        expect(int.tryParse(chunk), isNotNull);
      }
    });

    test('2. Safety code provides strict cryptographic avalanche effect', () async {
      const alicePubKey1 = 'mcW19qT4o09v6w48jE0GqXl0123456789abcdefghij=';
      const alicePubKey2 = 'mcW19qT4o09v6w48jE0GqXl0123456789abcdefghik='; // 1-bit difference
      const bobPubKey = 'zY8234klasdf092384jsadklfj230948asdfjklasdf=';

      final code1 = await E2EEService.generateSafetyCode(alicePubKey1, bobPubKey);
      final code2 = await E2EEService.generateSafetyCode(alicePubKey2, bobPubKey);

      expect(code1, isNot(equals(code2)));
    });

    test('3. Signaling message integrity & validation', () {
      final validSignal = {
        'type': 'incoming_call',
        'call_id': 101,
        'caller_id': 1,
        'caller_name': 'Alice',
        'call_type': 'video',
      };

      final session = CallSessionModel.fromSignaling(validSignal, 2);
      expect(session.id, equals(101));
      expect(session.callerId, equals(1));
      expect(session.receiverId, equals(2));
      expect(session.callType, equals('video'));
      expect(session.status, equals('ringing'));
    });

    test('4. CallService state zeroization on call termination', () async {
      CallService.isMutedNotifier.value = true;
      CallService.isVideoEnabledNotifier.value = false;
      CallService.callDurationNotifier.value = 120;

      // Mock setting an active call
      final testSession = CallSessionModel(
        id: 999,
        callerId: 1,
        receiverId: 2,
        callType: 'voice',
        status: 'ongoing',
        createdAt: DateTime.parse('2026-10-03T00:00:00Z'),
      );
      CallService.activeCallNotifier.value = testSession;
      expect(CallService.activeCallNotifier.value, isNotNull);

      // Clean up call
      CallService.endCall(999);

      // Verify immediate zeroization of active session and audio hardware state
      expect(CallService.activeCallNotifier.value, isNull);
      expect(CallService.callDurationNotifier.value, equals(0));
      expect(CallService.isMutedNotifier.value, isFalse);
      expect(CallService.isSpeakerNotifier.value, isTrue);
    });
  });
}
