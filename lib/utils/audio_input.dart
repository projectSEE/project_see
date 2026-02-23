import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Audio input helper for capturing PCM audio for Gemini Live API.
/// Records 16-bit PCM mono at 16kHz sample rate.
///
/// Uses Android hardware AEC (Acoustic Echo Cancellation) via
/// voiceCommunication audio source to prevent speaker → mic feedback.
class AudioInput {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSubscription;
  bool _isRecording = false;

  /// Initialize the audio input (request permissions if needed)
  Future<void> init() async {
    // Permissions are handled by the record package
  }

  /// Start recording and return a stream of audio data
  Future<Stream<Uint8List>?> startRecordingStream() async {
    if (_isRecording) return null;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    _isRecording = true;
    
    // Configure for Live API requirements: 16-bit PCM mono at 16kHz
    // ★ Uses voiceCommunication source for hardware AEC + noise suppression
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: 16000,
        androidConfig: AndroidRecordConfig(
          // voiceCommunication enables Android's built-in:
          //  • AcousticEchoCanceler — subtracts speaker output from mic
          //  • NoiseSuppressor — reduces background noise
          //  • AutomaticGainControl — normalizes volume
          audioSource: AndroidAudioSource.voiceCommunication,
          // modeInCommunication optimizes the audio pipeline for
          // two-way communication (like a phone call)
          audioManagerMode: AudioManagerMode.modeInCommunication,
          // Don't mute other audio — we play AI speech through speaker
          muteAudio: false,
        ),
      ),
    );

    return stream;
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    await _recorder.stop();
    _isRecording = false;
  }

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Dispose resources
  Future<void> dispose() async {
    await stopRecording();
    await _recorder.dispose();
  }
}
