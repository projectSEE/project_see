import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Service for playing raw PCM audio from Gemini Live API
/// Gemini Live returns PCM 16-bit, 24kHz, mono audio
class AudioPlayerService {
  AudioPlayer? _player;
  
  bool _isInitialized = false;
  bool _isPlaying = false;
  
  // Accumulate audio chunks for smoother playback
  final List<Uint8List> _pendingChunks = [];
  Timer? _playbackTimer;
  int _fileCounter = 0;
  
  bool get isPlaying => _isPlaying;
  
  /// Initialize the audio player
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _player = AudioPlayer();
      
      // Set audio to play at max volume
      await _player!.setVolume(1.0);
      
      _isInitialized = true;
      debugPrint('✅ AudioPlayerService initialized');
    } catch (e) {
      debugPrint('❌ AudioPlayerService init error: $e');
    }
  }
  
  /// Queue audio data for playback
  /// Accumulates chunks and plays them together for smoother audio
  void queueAudio(Uint8List audioData) {
    if (audioData.isEmpty) return;
    
    _pendingChunks.add(audioData);
    debugPrint('🔊 Queued audio: ${audioData.length} bytes (pending: ${_pendingChunks.length})');
    
    // Start a delayed timer to play accumulated audio
    // This allows multiple chunks to be combined
    _playbackTimer?.cancel();
    _playbackTimer = Timer(const Duration(milliseconds: 300), () {
      _playAccumulatedAudio();
    });
  }
  
  /// Play all accumulated audio chunks together
  Future<void> _playAccumulatedAudio() async {
    if (_pendingChunks.isEmpty || _player == null) return;
    
    // Combine all pending chunks
    final totalLength = _pendingChunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final combinedAudio = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in _pendingChunks) {
      combinedAudio.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _pendingChunks.clear();
    
    debugPrint('🔊 Playing combined audio: $totalLength bytes');
    
    await _playPCMAudio(combinedAudio);
  }
  
  /// Play PCM audio data by converting to WAV and playing
  Future<void> _playPCMAudio(Uint8List pcmData) async {
    if (pcmData.isEmpty || _player == null) {
      debugPrint('⚠️ Empty audio data or player not initialized');
      return;
    }
    
    _isPlaying = true;
    
    try {
      debugPrint('🔊 Converting PCM to WAV: ${pcmData.length} bytes');
      
      // Convert PCM to WAV format
      final wavData = _pcmToWav(pcmData, sampleRate: 24000, channels: 1, bitsPerSample: 16);
      debugPrint('🔊 WAV data created: ${wavData.length} bytes');
      
      // Write to temp file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/gemini_audio_${_fileCounter++}.wav');
      await tempFile.writeAsBytes(wavData);
      
      debugPrint('🔊 Saved to: ${tempFile.path}');
      
      // Stop any current playback first
      await _player!.stop();
      
      // Set and play the file
      await _player!.setFilePath(tempFile.path);
      await _player!.setVolume(1.0);  // Ensure max volume
      
      debugPrint('🔊 Starting playback...');
      await _player!.play();
      
      // Wait for playback to complete
      await _player!.processingStateStream
          .firstWhere((state) => state == ProcessingState.completed)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => ProcessingState.completed,
          );
      
      debugPrint('✅ Audio playback completed');
      
      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {}
      
    } catch (e, stackTrace) {
      debugPrint('❌ Audio playback error: $e');
      debugPrint('Stack: $stackTrace');
    } finally {
      _isPlaying = false;
    }
  }
  
  /// Convert raw PCM data to WAV format
  Uint8List _pcmToWav(Uint8List pcmData, {
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;
    
    final header = ByteData(44);
    
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little);  // fmt chunk size
    header.setUint16(20, 1, Endian.little);   // audio format (1 = PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);
    
    // Combine header and PCM data
    final wavData = Uint8List(44 + dataSize);
    wavData.setRange(0, 44, header.buffer.asUint8List());
    wavData.setRange(44, 44 + dataSize, pcmData);
    
    return wavData;
  }
  
  /// Stop playback and clear queue
  Future<void> stop() async {
    _playbackTimer?.cancel();
    _pendingChunks.clear();
    await _player?.stop();
    _isPlaying = false;
    debugPrint('🔇 Audio stopped');
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _player?.dispose();
    _player = null;
    _isInitialized = false;
  }
}
