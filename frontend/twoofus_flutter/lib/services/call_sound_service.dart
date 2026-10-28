import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class CallSoundService {
  CallSoundService._();
  static final CallSoundService instance = CallSoundService._();

  AudioPlayer? _ringPlayer;
  AudioPlayer? _effectPlayer;

  bool _isPlayingRing = false;

  /// Plays outgoing dial/ringback tone in a loop
  Future<void> playDialTone() async {
    try {
      await stopRingtone();
      _ringPlayer = AudioPlayer();
      await _ringPlayer!.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer!.setVolume(0.5);
      await _ringPlayer!.play(AssetSource('sounds/dial_tone.wav'));
      _isPlayingRing = true;
    } catch (e) {
      if (kDebugMode) print("[CallSoundService] playDialTone error: $e");
    }
  }

  /// Plays incoming melodic ringtone in a loop
  Future<void> playIncomingRingtone() async {
    try {
      await stopRingtone();
      _ringPlayer = AudioPlayer();
      await _ringPlayer!.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer!.setVolume(0.85);
      await _ringPlayer!.play(AssetSource('sounds/incoming_ringtone.wav'));
      _isPlayingRing = true;
    } catch (e) {
      if (kDebugMode) print("[CallSoundService] playIncomingRingtone error: $e");
    }
  }

  /// Plays cheerful connect chime once
  Future<void> playCallConnect() async {
    try {
      await stopRingtone();
      _effectPlayer?.dispose();
      _effectPlayer = AudioPlayer();
      await _effectPlayer!.setVolume(0.7);
      await _effectPlayer!.play(AssetSource('sounds/call_connect.wav'));
    } catch (e) {
      if (kDebugMode) print("[CallSoundService] playCallConnect error: $e");
    }
  }

  /// Plays soft end/disconnect chime once
  Future<void> playCallEnd() async {
    try {
      await stopRingtone();
      _effectPlayer?.dispose();
      _effectPlayer = AudioPlayer();
      await _effectPlayer!.setVolume(0.7);
      await _effectPlayer!.play(AssetSource('sounds/call_end.wav'));
    } catch (e) {
      if (kDebugMode) print("[CallSoundService] playCallEnd error: $e");
    }
  }

  /// Stops any currently looping dial or incoming ringtones
  Future<void> stopRingtone() async {
    if (_ringPlayer != null) {
      try {
        await _ringPlayer!.stop();
        await _ringPlayer!.dispose();
      } catch (_) {}
      _ringPlayer = null;
    }
    _isPlayingRing = false;
  }

  bool get isPlayingRing => _isPlayingRing;

  void dispose() {
    stopRingtone();
    _effectPlayer?.dispose();
    _effectPlayer = null;
  }
}

