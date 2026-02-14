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

    // Wait for the TTS engine to bind (Android needs time to connect)
    bool engineReady = false;
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        final engines = await _flutterTts.getEngines;
        if (engines != null && (engines as List).isNotEmpty) {
          engineReady = true;
          debugPrint('TTS: Engine bound after ${attempt + 1} attempt(s)');
          break;
        }
      } catch (e) {
        debugPrint('TTS: Engine not ready yet (attempt ${attempt + 1}/5)');
      }
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!engineReady) {
      debugPrint('TTS: WARNING - Engine not bound after retries, proceeding anyway');
    }

    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5); // Slightly slower for clarity
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Try to set Malaysian English if available
    try {
      final languages = await _flutterTts.getLanguages;
      if (languages != null && (languages as List).contains('en-MY')) {
        await _flutterTts.setLanguage('en-MY');
      }
    } catch (e) {
      debugPrint('TTS: Could not check languages: $e');
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
    debugPrint('TTS: Initialized successfully');
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
