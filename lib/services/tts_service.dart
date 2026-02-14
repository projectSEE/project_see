import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Service for text-to-speech announcements.
///
/// The native flutter_tts plugin handles engine binding internally —
/// if speak() is called before the engine is bound, the native side
/// queues the call and replays it once the engine connects.
/// We do NOT poll or block during init.
class TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;
  String _lastSpoken = '';
  DateTime _lastSpokenTime = DateTime.now();

  /// Initialize TTS — non-blocking, just sets handlers and config
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _flutterTts.setStartHandler(() => _isSpeaking = true);
    _flutterTts.setCompletionHandler(() => _isSpeaking = false);
    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      debugPrint('TTS Error: $msg');
    });

    // These calls are queued by the native plugin if engine isn't bound yet.
    // They will execute automatically once the engine connects.
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      debugPrint('TTS: Config queued/error: $e');
    }

    debugPrint('TTS: Initialized ✅');
  }

  /// Speak a message (with duplicate prevention)
  Future<void> speak(String message, {bool force = false}) async {
    if (!_isInitialized) await initialize();

    // Prevent duplicate announcements within 2 seconds
    final now = DateTime.now();
    if (!force &&
        message == _lastSpoken &&
        now.difference(_lastSpokenTime).inSeconds < 2) {
      return;
    }

    if (_isSpeaking && !force) return;

    if (force) {
      try { await _flutterTts.stop(); } catch (_) {}
    }

    _lastSpoken = message;
    _lastSpokenTime = now;

    try {
      await _flutterTts.speak(message);
    } catch (e) {
      debugPrint('TTS: speak error: $e');
    }
  }

  /// Speak an urgent warning (interrupts current speech)
  Future<void> speakUrgent(String message) async {
    await speak(message, force: true);
  }

  /// Announce obstacle detection results
  Future<void> announceObstacle(String label, String position, bool isClose) async {
    String urgency = isClose ? 'Warning!' : '';
    String distance = isClose ? 'close' : 'ahead';
    String message = '$urgency $label $distance on your $position'.trim();

    if (isClose) {
      await speakUrgent(message);
    } else {
      await speak(message);
    }
  }

  /// Stop speaking
  Future<void> stop() async {
    try { await _flutterTts.stop(); } catch (_) {}
    _isSpeaking = false;
  }

  bool get isSpeaking => _isSpeaking;

  Future<void> dispose() async {
    try { await _flutterTts.stop(); } catch (_) {}
  }
}
