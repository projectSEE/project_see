import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// Audio output helper for playing PCM audio from Gemini Live API.
/// Plays 16-bit PCM mono at 24kHz sample rate.
class AudioOutput {
  bool _isInitialized = false;
  bool _isPlaying = false;
  
  /// Initialize the audio output
  Future<void> init() async {
    if (_isInitialized) return;
    
    // Configure for Live API output: 16-bit PCM mono at 24kHz
    await FlutterPcmSound.setup(
      sampleRate: 24000,
      channelCount: 1,
    );
    
    // Set a callback for when audio finishes (optional)
    FlutterPcmSound.setFeedCallback((int remainingFrames) {
      // Called when audio buffer needs more data
    });
    
    _isInitialized = true;
  }

  /// Start playing audio stream
  Future<void> playStream() async {
    if (!_isInitialized) {
      await init();
    }
    _isPlaying = true;
  }

  /// Add audio data to the playback stream
  Future<void> addAudioStream(Uint8List audioData) async {
    if (!_isInitialized) {
      await init();
    }
    
    if (audioData.isNotEmpty) {
      await FlutterPcmSound.feed(PcmArrayInt16.fromList(
        audioData.buffer.asInt16List(),
      ));
    }
  }

  /// Stop playing
  Future<void> stop() async {
    if (!_isPlaying) return;
    await FlutterPcmSound.release();
    _isPlaying = false;
  }

  /// Check if currently playing
  bool get isPlaying => _isPlaying;

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
  }
}
