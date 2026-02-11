import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for fast image stream processing
/// Uses native code for YUV to JPEG conversion
class ImageStreamService {
  static const MethodChannel _channel = MethodChannel('image_converter_channel');
  
  bool _isActive = false;
  int _frameSkipCount = 0;
  int _frameSkipInterval = 5; // Process every 5th frame (6 FPS at 30 FPS camera)
  
  Function(Uint8List jpegBytes)? onImageReady;
  
  bool get isActive => _isActive;
  
  /// Start processing - call this when entering Live mode
  void start({int frameSkip = 5}) {
    _isActive = true;
    _frameSkipCount = 0;
    _frameSkipInterval = frameSkip;
    debugPrint('📷 ImageStreamService started (skip=$frameSkip)');
  }
  
  /// Stop processing
  void stop() {
    _isActive = false;
    debugPrint('📷 ImageStreamService stopped');
  }
  
  /// Process a CameraImage from the existing image stream
  /// Call this from your existing _processStreamImage callback
  void processFrame(CameraImage image, CameraDescription camera) {
    if (!_isActive || onImageReady == null) return;
    
    // Skip frames to reduce load
    _frameSkipCount++;
    if (_frameSkipCount < _frameSkipInterval) return;
    _frameSkipCount = 0;
    
    // Convert asynchronously
    _convertImageAsync(image);
  }
  
  /// Convert CameraImage to JPEG asynchronously
  Future<void> _convertImageAsync(CameraImage image) async {
    try {
      Uint8List? jpegBytes;
      
      // Try native conversion first (faster)
      try {
        jpegBytes = await _convertNative(image);
      } catch (e) {
        debugPrint('⚠️ Native conversion failed: $e');
        // Fallback to Dart (slower)
        jpegBytes = await compute(_convertDartStatic, _CameraImageData.fromImage(image));
      }
      
      if (jpegBytes != null && jpegBytes.isNotEmpty && _isActive) {
        debugPrint('📷 Fast frame: ${jpegBytes.length} bytes');
        onImageReady?.call(jpegBytes);
      }
    } catch (e) {
      debugPrint('❌ Frame conversion error: $e');
    }
  }
  
  /// Native conversion using platform channel
  Future<Uint8List?> _convertNative(CameraImage image) async {
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
      'quality': 40, // Lower quality for faster transfer
    };
    
    final result = await _channel.invokeMethod<Uint8List>('convertYuvToJpeg', args);
    return result;
  }
  
  void dispose() {
    stop();
    onImageReady = null;
  }
}

/// Data class for passing to isolate
class _CameraImageData {
  final int width;
  final int height;
  final Uint8List yPlane;
  final int yRowStride;
  final Uint8List? uPlane;
  final int? uRowStride;
  final Uint8List? vPlane;
  final int? vRowStride;
  final int? uvPixelStride;
  
  _CameraImageData({
    required this.width,
    required this.height,
    required this.yPlane,
    required this.yRowStride,
    this.uPlane,
    this.uRowStride,
    this.vPlane,
    this.vRowStride,
    this.uvPixelStride,
  });
  
  factory _CameraImageData.fromImage(CameraImage image) {
    return _CameraImageData(
      width: image.width,
      height: image.height,
      yPlane: Uint8List.fromList(image.planes[0].bytes),
      yRowStride: image.planes[0].bytesPerRow,
      uPlane: image.planes.length > 1 ? Uint8List.fromList(image.planes[1].bytes) : null,
      uRowStride: image.planes.length > 1 ? image.planes[1].bytesPerRow : null,
      vPlane: image.planes.length > 2 ? Uint8List.fromList(image.planes[2].bytes) : null,
      vRowStride: image.planes.length > 2 ? image.planes[2].bytesPerRow : null,
      uvPixelStride: image.planes.length > 1 ? image.planes[1].bytesPerPixel : null,
    );
  }
}

/// Static function for compute() - converts YUV to JPEG
Uint8List? _convertDartStatic(_CameraImageData data) {
  try {
    final int targetWidth = 320;
    final int targetHeight = 240;
    
    final double scaleX = data.width / targetWidth;
    final double scaleY = data.height / targetHeight;
    
    // Create grayscale JPEG-like (actually simple format)
    final rgbBytes = Uint8List(targetWidth * targetHeight * 3);
    
    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        final int srcX = (x * scaleX).toInt();
        final int srcY = (y * scaleY).toInt();
        
        final int yIndex = srcY * data.yRowStride + srcX;
        final int yValue = yIndex < data.yPlane.length ? data.yPlane[yIndex] : 128;
        
        final int rgbIndex = (y * targetWidth + x) * 3;
        rgbBytes[rgbIndex] = yValue;
        rgbBytes[rgbIndex + 1] = yValue;
        rgbBytes[rgbIndex + 2] = yValue;
      }
    }
    
    return _encodeToBmp(rgbBytes, targetWidth, targetHeight);
  } catch (e) {
    return null;
  }
}

/// Encode RGB to BMP format
Uint8List _encodeToBmp(Uint8List rgb, int width, int height) {
  final int imageSize = width * height * 3;
  final int fileSize = 54 + imageSize;
  
  final bmp = Uint8List(fileSize);
  final data = ByteData.view(bmp.buffer);
  
  bmp[0] = 0x42; // B
  bmp[1] = 0x4D; // M
  data.setUint32(2, fileSize, Endian.little);
  data.setUint32(10, 54, Endian.little);
  
  data.setUint32(14, 40, Endian.little);
  data.setInt32(18, width, Endian.little);
  data.setInt32(22, -height, Endian.little);
  data.setUint16(26, 1, Endian.little);
  data.setUint16(28, 24, Endian.little);
  data.setUint32(34, imageSize, Endian.little);
  
  int offset = 54;
  for (int i = 0; i < rgb.length; i += 3) {
    bmp[offset++] = rgb[i + 2];
    bmp[offset++] = rgb[i + 1];
    bmp[offset++] = rgb[i];
  }
  
  return bmp;
}
