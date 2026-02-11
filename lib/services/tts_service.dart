import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Service for text-to-speech announcements
class TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;
  String _lastSpoken = '';
  DateTime _lastSpokenTime = DateTime.now();

  /// Initialize TTS with Malaysian/English settings
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5); // Slightly slower for clarity
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Try to set Malaysian English if available
    final languages = await _flutterTts.getLanguages;
    if (languages.contains('en-MY')) {
      await _flutterTts.setLanguage('en-MY');
    }

    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      debugPrint('TTS Error: $msg');
    });

    _isInitialized = true;
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

    // If already speaking, queue or skip based on priority
    if (_isSpeaking && !force) {
      return;
    }

    if (force) {
      await _flutterTts.stop();
    }

    _lastSpoken = message;
    _lastSpokenTime = now;
    await _flutterTts.speak(message);
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
    await _flutterTts.stop();
    _isSpeaking = false;
  }

  /// Check if currently speaking
  bool get isSpeaking => _isSpeaking;

  /// Dispose resources
  Future<void> dispose() async {
    await _flutterTts.stop();
  }
}
