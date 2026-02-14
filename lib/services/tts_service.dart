import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Service for text-to-speech announcements
class TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isConfigured = false;
  bool _isSpeaking = false;
  String _lastSpoken = '';
  DateTime _lastSpokenTime = DateTime.now();

  /// Initialize TTS — just registers handlers, doesn't block on engine
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

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

    debugPrint('TTS: Handlers registered, engine will configure on first speak');

    // Schedule engine configuration after a delay
    // This gives the Android TTS engine time to bind
    Future.delayed(const Duration(seconds: 2), () => _configureEngine());
  }

  /// Configure TTS engine settings (called after engine has had time to bind)
  Future<void> _configureEngine() async {
    if (_isConfigured) return;
    
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isConfigured = true;
      debugPrint('TTS: Engine configured ✅');
    } catch (e) {
      debugPrint('TTS: Config error (will retry): $e');
    }
  }

  /// Speak a message (with duplicate prevention)
  Future<void> speak(String message, {bool force = false}) async {
    if (!_isInitialized) await initialize();

    // Ensure engine is configured before speaking
    if (!_isConfigured) {
      await _configureEngine();
    }

    // Prevent duplicate announcements within 2 seconds
    final now = DateTime.now();
    if (!force && 
        message == _lastSpoken && 
        now.difference(_lastSpokenTime).inSeconds < 2) {
      return;
    }

    // If already speaking, skip unless forced
    if (_isSpeaking && !force) {
      return;
    }

    if (force) {
      await _flutterTts.stop();
    }

    _lastSpoken = message;
    _lastSpokenTime = now;
    
    try {
      await _flutterTts.speak(message);
    } catch (e) {
      debugPrint('TTS: speak error: $e');
      // If speak fails, engine might not be bound yet — try reconfiguring
      _isConfigured = false;
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
