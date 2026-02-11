import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Service for capturing microphone audio and streaming it
/// Based on official Flutter demo: https://github.com/flutter/demos
class AudioStreamService extends ChangeNotifier {
  AudioRecorder? _recorder;
  late Stream<Uint8List> audioStream;
  bool isRecording = false;
  bool isPaused = false;

  final RecordConfig recordConfig = const RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    echoCancel: true,
    noiseSuppress: true,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceCommunication,
    ),
  );

  Future<void> init() async {
    _recorder = AudioRecorder();
    await checkPermission();
  }

  @override
  void dispose() {
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> checkPermission() async {
    final hasPermission = await _recorder!.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }
  }

  Future<Stream<Uint8List>?> startRecordingStream() async {
    try {
      if (_recorder == null) {
        _recorder = AudioRecorder();
        await checkPermission();
      }
      
      audioStream = (await _recorder!.startStream(recordConfig)).asBroadcastStream();
      isRecording = true;
      debugPrint('🎤 Microphone recording started (PCM 16kHz)');
      notifyListeners();
      return audioStream;
    } catch (e) {
      debugPrint('❌ Start recording error: $e');
      return null;
    }
  }

  Future<void> stopRecording() async {
    try {
      await _recorder!.stop();
      isRecording = false;
      _recorder?.dispose();
      _recorder = AudioRecorder();
      debugPrint('🎤 Microphone recording stopped');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Stop recording error: $e');
    }
  }

  Future<void> togglePauseRecording() async {
    isPaused ? await _recorder!.resume() : await _recorder!.pause();
    isPaused = !isPaused;
    notifyListeners();
  }
}
