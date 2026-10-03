import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/session.dart';
import 'api_service.dart';

/// Secure, authenticated WebSocket signaling client for 1-to-1 WebRTC calls.
class CallSignalingClient {
  CallSignalingClient._();
  static final CallSignalingClient instance = CallSignalingClient._();

  WebSocketChannel? _channel;
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _isManualDisconnect = false;
  int _reconnectAttempts = 0;

  /// Connects to the authenticated call signaling WebSocket endpoint
  Future<void> connect() async {
    _isManualDisconnect = false;
    _reconnectTimer?.cancel();

    final token = await Session.getToken();
    if (token == null || token.isEmpty) {
      if (kDebugMode) {
        print("[CallSignalingClient] Cannot connect: missing auth token");
      }
      return;
    }

    try {
      final wsUrl = ApiService.wsCallUrl;
      final uri = Uri.parse("$wsUrl?token=$token");

      if (kDebugMode) {
        print("[CallSignalingClient] Connecting to $wsUrl...");
      }

      _channel?.sink.close();
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (dynamic rawMessage) {
          _reconnectAttempts = 0;
          try {
            final Map<String, dynamic> msg =
                jsonDecode(rawMessage.toString()) as Map<String, dynamic>;
            final type = msg['type'];

            if (type == 'authenticated') {
              isConnectedNotifier.value = true;
              _startPingTimer();
              if (kDebugMode) {
                print("[CallSignalingClient] Authenticated ready on server");
              }
            } else if (type == 'pong') {
              // Heartbeat acknowledged
            }

            _messageController.add(msg);
          } catch (e) {
            if (kDebugMode) {
              print("[CallSignalingClient] Parse error: $e");
            }
          }
        },
        onError: (dynamic error) {
          if (kDebugMode) {
            print("[CallSignalingClient] Stream error: $error");
          }
          _handleDisconnect();
        },
        onDone: () {
          if (kDebugMode) {
            print("[CallSignalingClient] Connection closed");
          }
          _handleDisconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (kDebugMode) {
        print("[CallSignalingClient] Connection exception: $e");
      }
      _handleDisconnect();
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      sendSignal({'type': 'ping'});
    });
  }

  void _handleDisconnect() {
    _pingTimer?.cancel();
    isConnectedNotifier.value = false;

    if (!_isManualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delaySeconds = (_reconnectAttempts * 2).clamp(2, 20);
    if (kDebugMode) {
      print("[CallSignalingClient] Reconnecting in ${delaySeconds}s (attempt $_reconnectAttempts)...");
    }
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      connect();
    });
  }

  /// Sends a raw JSON signaling map to the backend
  void sendSignal(Map<String, dynamic> data) {
    if (_channel != null) {
      try {
        final payload = jsonEncode(data);
        _channel!.sink.add(payload);
      } catch (e) {
        if (kDebugMode) {
          print("[CallSignalingClient] Failed to send signal: $e");
        }
      }
    }
  }

  // ── High-Level Signaling Event Helpers ─────────────────────────────────────

  /// Sends outgoing call invitation
  void sendInvite({
    required int targetId,
    required String callType, // "voice" | "video"
  }) {
    sendSignal({
      'type': 'call_invite',
      'target_id': targetId,
      'call_type': callType,
    });
  }

  /// Sends call ringing acknowledgment
  void sendRinging({required int callId, required int targetId}) {
    sendSignal({
      'type': 'call_ringing',
      'call_id': callId,
      'target_id': targetId,
    });
  }

  /// Accepts an incoming call
  void sendAccept({required int callId}) {
    sendSignal({
      'type': 'call_accept',
      'call_id': callId,
    });
  }

  /// Declines or rejects an incoming call
  void sendReject({required int callId, String reason = 'declined'}) {
    sendSignal({
      'type': 'call_reject',
      'call_id': callId,
      'reason': reason,
    });
  }

  /// Cancels an outgoing call before partner answers
  void sendCancel({required int callId}) {
    sendSignal({
      'type': 'call_cancel',
      'call_id': callId,
    });
  }

  /// Ends an ongoing or ringing call
  void sendEnd({required int callId, String reason = 'normal_hangup'}) {
    sendSignal({
      'type': 'call_end',
      'call_id': callId,
      'reason': reason,
    });
  }

  /// Sends WebRTC SDP Offer
  void sendWebRtcOffer({
    required int callId,
    required String sdp,
    String type = 'offer',
  }) {
    sendSignal({
      'type': 'webrtc_offer',
      'call_id': callId,
      'payload': {
        'sdp': sdp,
        'type': type,
      },
    });
  }

  /// Sends WebRTC SDP Answer
  void sendWebRtcAnswer({
    required int callId,
    required String sdp,
    String type = 'answer',
  }) {
    sendSignal({
      'type': 'webrtc_answer',
      'call_id': callId,
      'payload': {
        'sdp': sdp,
        'type': type,
      },
    });
  }

  /// Sends WebRTC ICE Candidate
  void sendWebRtcIceCandidate({
    required int callId,
    required Map<String, dynamic> candidatePayload,
  }) {
    sendSignal({
      'type': 'webrtc_ice_candidate',
      'call_id': callId,
      'payload': candidatePayload,
    });
  }

  /// Disconnects the WebSocket channel and stops reconnecting
  void disconnect() {
    _isManualDisconnect = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    isConnectedNotifier.value = false;
  }
}
