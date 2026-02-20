import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Centralized Text-to-Speech service (Singleton).
///
/// Only ONE FlutterTts instance exists for the entire app.
/// Handles Xiaomi / MIUI devices that are slow to bind the TTS engine.
class TTSService {
  // ── Singleton ──
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  // ── State ──
  FlutterTts? _tts;
  bool _isReady = false;
  bool _isSpeaking = false;
  String _lastSpoken = '';
  DateTime _lastSpokenTime = DateTime(2000);
  Completer<void>? _initCompleter;

  // ── Public getters ──
  bool get isReady => _isReady;
  bool get isSpeaking => _isSpeaking;

  // ── Initialization ──

  /// Call once at app startup. Safe to call multiple times.
  /// Returns a Future that completes when the engine is ready.
  Future<void> initialize() async {
    // Already ready
    if (_isReady && _tts != null) return;

    // Already initializing — wait for it
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      debugPrint('TTS: Starting initialization...');

      // Create a fresh instance
      _tts = FlutterTts();

      // Register handlers BEFORE any engine calls
      _tts!.setStartHandler(() {
        _isSpeaking = true;
      });
      _tts!.setCompletionHandler(() {
        _isSpeaking = false;
        debugPrint('TTS: Speech completed');
      });
      _tts!.setErrorHandler((msg) {
        _isSpeaking = false;
        debugPrint('TTS Error: $msg');
      });

      // Try to configure — retry up to 5 times with increasing delay
      // This is critical for Xiaomi/MIUI which takes longer to bind
      bool configured = false;
      for (int attempt = 1; attempt <= 5; attempt++) {
        try {
          // Wait before each attempt (increasing delay)
          await Future.delayed(Duration(seconds: attempt));

          // setLanguage will throw/fail if the engine isn't bound
          await _tts!.setLanguage('en-US');
          await _tts!.setSpeechRate(0.5);
          await _tts!.setVolume(1.0);
          await _tts!.setPitch(1.0);
          await _tts!.awaitSpeakCompletion(true);

          configured = true;
          debugPrint('TTS: Configured successfully on attempt $attempt');
          break;
        } catch (e) {
          debugPrint('TTS: Configuration attempt $attempt failed: $e');
          if (attempt == 5) {
            debugPrint('TTS: All configuration attempts failed');
          }
        }
      }

      if (!configured) {
        // Even if configuration failed, mark as "ready" so speak()
        // can still try — the engine may bind later
        debugPrint('TTS: Could not configure, will retry on first speak()');
      }

      _isReady = true;
      debugPrint('TTS: Initialization complete (configured=$configured)');

      if (!_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
    } catch (e) {
      debugPrint('TTS: Initialization error: $e');
      _isReady = false;
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.completeError(e);
      }
    } finally {
      _initCompleter = null;
    }
  }

  // ── Speaking ──

  /// Speak a message.
  ///
  /// [force] — interrupt current speech.
  /// [preventDuplicates] — skip if same message was spoken < 2 s ago.
  Future<void> speak(
    String message, {
    bool force = false,
    bool preventDuplicates = true,
  }) async {
    if (message.trim().isEmpty) return;

    // Lazy init
    if (!_isReady || _tts == null) {
      await initialize();
    }

    // Duplicate guard
    if (preventDuplicates && !force) {
      final now = DateTime.now();
      if (message == _lastSpoken &&
          now.difference(_lastSpokenTime).inSeconds < 2) {
        return;
      }
      if (_isSpeaking) return;
    }

    // Stop current speech if forcing
    if (force && _isSpeaking) {
      try {
        await _tts!.stop();
      } catch (_) {}
    }

    _lastSpoken = message;
    _lastSpokenTime = DateTime.now();

    try {
      final result = await _tts!.speak(message);
      debugPrint('TTS: speak() result=$result');

      // result != 1 means the engine rejected the call
      if (result != 1) {
        debugPrint('TTS: speak() failed (result=$result), retrying after delay...');
        // Wait for the engine to bind, then retry once
        await Future.delayed(const Duration(seconds: 3));
        final retry = await _tts!.speak(message);
        debugPrint('TTS: retry speak() result=$retry');
      }
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }

  /// Speak urgently — interrupts current speech, no duplicate check.
  Future<void> speakUrgent(String message) async {
    await speak(message, force: true, preventDuplicates: false);
  }

  /// Announce an obstacle detection result.
  Future<void> announceObstacle(
    String label,
    String position,
    bool isClose,
  ) async {
    final urgency = isClose ? 'Warning!' : '';
    final distance = isClose ? 'close' : 'ahead';
    final message = '$urgency $label $distance on your $position'.trim();

    if (isClose) {
      await speakUrgent(message);
    } else {
      await speak(message);
    }
  }

  // ── Control ──

  /// Stop any current speech.
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
    _isSpeaking = false;
  }

  /// Set speech rate (0.0 – 1.0).
  Future<void> setSpeechRate(double rate) async {
    try {
      await _tts?.setSpeechRate(rate.clamp(0.0, 1.0));
    } catch (_) {}
  }

  /// Clean up. Normally never called for a singleton.
  Future<void> dispose() async {
    await stop();
    _tts = null;
    _isReady = false;
  }
}
