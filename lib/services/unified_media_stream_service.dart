import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_ai/firebase_ai.dart';

/// Unified service that merges audio and video into a single stream
/// for Gemini Live API
/// 
/// Based on Firebase documentation:
/// - Video: 1 FPS recommended, 768x768 resolution
/// - Audio: PCM 16kHz mono
class UnifiedMediaStreamService {
  static const MethodChannel _channel = MethodChannel('image_converter_channel');
  
  StreamController<InlineDataPart>? _mediaStreamController;
  bool _isActive = false;
  bool _isProcessingVideo = false;
  
  // Video frame timing
  DateTime? _lastVideoTime;
  static const Duration _videoInterval = Duration(seconds: 1); // 1 FPS as recommended
  int _videoFrameCount = 0;
  int _audioChunkCount = 0;
  
  Stream<InlineDataPart>? get mediaStream => _mediaStreamController?.stream;
  bool get isActive => _isActive;
  
  /// Start the unified media stream
  void start() {
    if (_isActive) return;
    
    _mediaStreamController = StreamController<InlineDataPart>.broadcast();
    _isActive = true;
    _lastVideoTime = null;
    _videoFrameCount = 0;
    _audioChunkCount = 0;
    
    debugPrint('📹 UnifiedMediaStream started (1 FPS video)');
  }
  
  /// Add audio data to the stream
  void addAudio(Uint8List audioData) {
    if (!_isActive || _mediaStreamController == null || _mediaStreamController!.isClosed) return;
    
    try {
      _mediaStreamController!.add(InlineDataPart('audio/pcm', audioData));
      _audioChunkCount++;
      
      // Log every 50 audio chunks
      if (_audioChunkCount % 50 == 0) {
        debugPrint('🎤 Audio chunks sent: $_audioChunkCount');
      }
    } catch (e) {
      debugPrint('❌ Error adding audio: $e');
    }
  }
  
  /// Add video frame to the stream
  void addVideo(Uint8List imageData) {
    if (!_isActive || _mediaStreamController == null || _mediaStreamController!.isClosed) return;
    
    try {
      // Use image/jpeg MIME type
      _mediaStreamController!.add(InlineDataPart('image/jpeg', imageData));
      _videoFrameCount++;
      debugPrint('📷 Video frame #$_videoFrameCount sent: ${imageData.length} bytes');
    } catch (e) {
      debugPrint('❌ Error adding video: $e');
    }
  }
  
  /// Process camera frame and add to stream (1 FPS)
  Future<void> processCameraFrame(CameraImage image) async {
    if (!_isActive || _isProcessingVideo) return;
    
    // Enforce 1 FPS rate limit
    final now = DateTime.now();
    if (_lastVideoTime != null && now.difference(_lastVideoTime!) < _videoInterval) {
      return;
    }
    
    _isProcessingVideo = true;
    _lastVideoTime = now;
    
    try {
      debugPrint('📷 Converting camera frame...');
      final jpegData = await _convertToJpeg(image);
      
      if (jpegData != null && jpegData.isNotEmpty && _isActive) {
        addVideo(jpegData);
      } else {
        debugPrint('⚠️ Video conversion returned empty data');
      }
    } catch (e) {
      debugPrint('❌ Video frame processing error: $e');
    } finally {
      _isProcessingVideo = false;
    }
  }
  
  /// Convert camera image to JPEG using native code
  Future<Uint8List?> _convertToJpeg(CameraImage image) async {
    try {
      final Map<String, dynamic> args = {
        'width': image.width,
        'height': image.height,
        'yPlane': image.planes[0].bytes,
        'yRowStride': image.planes[0].bytesPerRow,
        'uPlane': image.planes.length > 1 ? image.planes[1].bytes : null,
        'uRowStride': image.planes.length > 1 ? image.planes[1].bytesPerRow : null,
        'vPlane': image.planes.length > 2 ? image.planes[2].bytes : null,
        'vRowStride': image.planes.length > 2 ? image.planes[2].bytesPerRow : null,
        'uvPixelStride': image.planes.length > 1 ? image.planes[1].bytesPerPixel : null,
        'quality': 60, // Higher quality for better recognition
      };
      
      final result = await _channel.invokeMethod<Uint8List>('convertYuvToJpeg', args);
      debugPrint('📷 Native conversion result: ${result?.length ?? 0} bytes');
      return result;
    } catch (e) {
      debugPrint('❌ Native conversion failed: $e');
      return null;
    }
  }
  
  /// Stop the stream
  void stop() {
    if (!_isActive) return;
    
    _isActive = false;
    
    try {
      _mediaStreamController?.close();
    } catch (e) {
      debugPrint('⚠️ Error closing stream: $e');
    }
    
    _mediaStreamController = null;
    _lastVideoTime = null;
    
    debugPrint('📹 UnifiedMediaStream stopped (sent $videoFrameCount video frames, $_audioChunkCount audio chunks)');
  }
  
  int get videoFrameCount => _videoFrameCount;
  int get audioChunkCount => _audioChunkCount;
  
  void dispose() {
    stop();
  }
}
