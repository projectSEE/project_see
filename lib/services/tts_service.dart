import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Service for text-to-speech announcements.
///
/// Uses a delayed initialization approach: the native Android TTS engine
/// needs time to bind to the TTS service. We delay configuration calls
/// and retry speak() if the first attempt fails.
class TTSService {
  FlutterTts? _flutterTts;
  bool _isInitialized = false;
  bool _isSpeaking = false;
  bool _engineReady = false;
  String _lastSpoken = '';
  DateTime _lastSpokenTime = DateTime.now();
  Timer? _bindCheckTimer;

  /// Initialize TTS — creates instance and schedules engine binding check
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _createTtsInstance();

    // Schedule periodic checks to configure the engine once it's bound
    // The native engine typically binds within 1-5 seconds
    int attempts = 0;
    _bindCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      if (_engineReady || attempts > 15) {
        timer.cancel();
        if (!_engineReady) {
          debugPrint('TTS: ⚠️ Engine never became ready after 30s');
        }
        return;
      }
      await _tryConfigureEngine(attempts);
    });

    debugPrint('TTS: Initialized, waiting for engine bind...');
  }

  void _createTtsInstance() {
    _flutterTts = FlutterTts();
    _flutterTts!.setStartHandler(() => _isSpeaking = true);
    _flutterTts!.setCompletionHandler(() {
      _isSpeaking = false;
      if (!_engineReady) {
        _engineReady = true;
        _bindCheckTimer?.cancel();
        debugPrint('TTS: Engine confirmed ready (speech completed) ✅');
      }
    });
    _flutterTts!.setErrorHandler((msg) {
      _isSpeaking = false;
      debugPrint('TTS Error: $msg');
    });
  }

  /// Try to configure and test the engine
  Future<void> _tryConfigureEngine(int attempt) async {
    if (_flutterTts == null) return;

    try {
      // Try setLanguage — this will fail silently if engine isn't bound
      await _flutterTts!.setLanguage('en-US');
      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.setVolume(1.0);
      await _flutterTts!.setPitch(1.0);

      // Try a silent test speak — if this succeeds, engine is ready
      // We use an empty-ish utterance to test
      final result = await _flutterTts!.speak(' ');
      if (result == 1) {
        _engineReady = true;
        _bindCheckTimer?.cancel();
        debugPrint('TTS: Engine ready on attempt $attempt ✅');
        await _flutterTts!.stop();
      } else {
        debugPrint('TTS: Attempt $attempt - speak returned $result, retrying...');
      }
    } catch (e) {
      debugPrint('TTS: Attempt $attempt - error: $e');
    }
  }

  /// Speak a message (with duplicate prevention)
  Future<void> speak(String message, {bool force = false}) async {
    if (!_isInitialized) await initialize();
    if (_flutterTts == null) return;

    // Prevent duplicate announcements within 2 seconds
    final now = DateTime.now();
    if (!force &&
        message == _lastSpoken &&
        now.difference(_lastSpokenTime).inSeconds < 2) {
      return;
    }

    if (_isSpeaking && !force) return;

    if (force) {
      try { await _flutterTts!.stop(); } catch (_) {}
    }

    _lastSpoken = message;
    _lastSpokenTime = now;

    try {
      final result = await _flutterTts!.speak(message);
      if (result == 1) {
        _engineReady = true;
      }
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
    try { await _flutterTts?.stop(); } catch (_) {}
    _isSpeaking = false;
  }

  bool get isSpeaking => _isSpeaking;

  Future<void> dispose() async {
    _bindCheckTimer?.cancel();
    try { await _flutterTts?.stop(); } catch (_) {}
  }
}
