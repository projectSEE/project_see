import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Audio output helper for playing PCM audio from Gemini Live API.
/// Plays 16-bit PCM mono at 24kHz sample rate.
///
/// ★ Uses native Android AudioTrack with USAGE_VOICE_COMMUNICATION
/// so that Android's hardware AEC (Acoustic Echo Canceler) can properly
/// subtract this audio from the microphone input — preventing the
/// speaker → mic feedback loop that interrupts the Live API.
class AudioOutput {
  static const _channel = MethodChannel('audio_output_channel');

  bool _isInitialized = false;
  bool _isPlaying = false;
  int _totalFedBytes = 0;
  int _feedErrors = 0;

  /// Initialize the native AudioTrack (VOICE_COMMUNICATION mode)
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await _channel.invokeMethod('init');
      _isInitialized = true;
      _isPlaying = true;
      _totalFedBytes = 0;
      _feedErrors = 0;
      debugPrint('✅ AudioOutput initialized (native AEC AudioTrack, 24kHz)');
    } catch (e) {
      debugPrint('❌ AudioOutput init FAILED: $e');
    }
  }

  /// Start playing audio stream (init if needed)
  Future<void> playStream() async {
    if (!_isInitialized) {
      await init();
    }
    _isPlaying = true;
    _totalFedBytes = 0;
    _feedErrors = 0;
    debugPrint('🔊 AudioOutput playStream() — ready to receive audio');
  }

  /// Add audio data to the playback stream
  Future<void> addAudioStream(Uint8List audioData) async {
    if (!_isInitialized) {
      debugPrint('⚠️ AudioOutput not initialized, skipping ${audioData.length} bytes');
      return;
    }

    if (audioData.isEmpty) return;

    try {
      await _channel.invokeMethod('feed', {'pcmData': audioData});
      _totalFedBytes += audioData.length;

      // Log periodically
      if (_totalFedBytes % 20000 < audioData.length) {
        debugPrint('🔊 Fed ${(_totalFedBytes / 1024).toStringAsFixed(0)}KB total');
      }
    } catch (e) {
      _feedErrors++;
      if (_feedErrors <= 5) {
        debugPrint('❌ AudioOutput feed error #$_feedErrors: $e');
      }
    }
  }

  /// Stop playing and release native resources
  Future<void> stop() async {
    if (!_isInitialized) return;
    debugPrint('🔊 AudioOutput stopping (fed ${(_totalFedBytes / 1024).toStringAsFixed(0)}KB, $_feedErrors errors)');
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('⚠️ AudioOutput stop error: $e');
    }
    _isPlaying = false;
    _isInitialized = false;
  }

  /// Hard barge-in: instantly flush the native audio buffer
  /// Use this when user interrupts — kills playback immediately
  Future<void> stopImmediately() async {
    if (!_isInitialized) return;
    debugPrint('🔇 BARGE-IN: flushing native audio buffer');
    try {
      await _channel.invokeMethod('flush');
      _totalFedBytes = 0;
    } catch (e) {
      debugPrint('⚠️ stopImmediately error: $e');
    }
  }

  /// Check if currently playing
  bool get isPlaying => _isPlaying;

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
  }
}
