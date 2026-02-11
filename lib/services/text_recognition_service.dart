import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Service for recognizing text in camera frames
/// Useful for reading signs, labels, room numbers, product names
class TextRecognitionService {
  TextRecognizer? _textRecognizer;
  bool _isProcessing = false;
  
  // Cache last recognized text to avoid repetition
  String _lastRecognizedText = '';
  DateTime _lastRecognitionTime = DateTime.now();
  
  bool get isProcessing => _isProcessing;
  
  /// Initialize the text recognizer
  Future<void> initialize() async {
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    debugPrint('✅ TextRecognitionService initialized');
  }
  
  /// Process a camera image and extract text
  Future<List<RecognizedTextBlock>> processImage(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_isProcessing || _textRecognizer == null) return [];
    
    _isProcessing = true;
    
    try {
      final inputImage = _buildInputImage(image, camera);
      if (inputImage == null) {
        _isProcessing = false;
        return [];
      }
      
      final recognizedText = await _textRecognizer!.processImage(inputImage);
      
      // Filter and format results
      final results = <RecognizedTextBlock>[];
      
      for (final block in recognizedText.blocks) {
        // Filter out small or low-confidence text
        if (block.text.length < 2) continue;
        
        // Calculate block size relative to image
        final blockArea = block.boundingBox.width * block.boundingBox.height;
        final imageArea = image.width * image.height;
        final relativeSize = blockArea / imageArea;
        
        // Only include reasonably sized text
        if (relativeSize > 0.005) {
          results.add(RecognizedTextBlock(
            text: block.text.trim(),
            relativeSize: relativeSize,
            position: _getPosition(block.boundingBox.center.dx, image.width.toDouble()),
          ));
        }
      }
      
      _isProcessing = false;
      return results;
      
    } catch (e) {
      debugPrint('❌ Text recognition error: $e');
      _isProcessing = false;
      return [];
    }
  }
  
  /// Check if text is new (not recently announced)
  bool isNewText(String text) {
    final now = DateTime.now();
    final timeSinceLast = now.difference(_lastRecognitionTime);
    
    // If same text within 10 seconds, skip
    if (text == _lastRecognizedText && timeSinceLast.inSeconds < 10) {
      return false;
    }
    
    _lastRecognizedText = text;
    _lastRecognitionTime = now;
    return true;
  }
  
  String _getPosition(double centerX, double imageWidth) {
    if (centerX < imageWidth / 3) return 'left';
    if (centerX > imageWidth * 2 / 3) return 'right';
    return 'center';
  }

  /// Build InputImage from CameraImage - handles different formats
  InputImage? _buildInputImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    // Get the image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    
    // For Android with YUV_420_888 format (3 planes)
    if (Platform.isAndroid && image.planes.length == 3) {
      // Try NV21 conversion
      try {
        final nv21 = _convertYUV420ToNV21(image);
        return InputImage.fromBytes(
          bytes: nv21,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: image.width,
          ),
        );
      } catch (e) {
        debugPrint('NV21 conversion failed: $e');
        return null;
      }
    }
    
    // Single plane format (NV21 or BGRA)
    if (image.planes.length == 1) {
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format ?? InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    return null;
  }

  /// Convert YUV_420_888 to NV21 format
  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    
    final int ySize = width * height;
    final int uvSize = (width * height) ~/ 2;
    
    final Uint8List nv21 = Uint8List(ySize + uvSize);
    
    // Copy Y plane
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        nv21[y * width + x] = yPlane.bytes[y * yPlane.bytesPerRow + x];
      }
    }
    
    // Interleave V and U planes (NV21 = VUVU...)
    final int uvWidth = width ~/ 2;
    final int uvHeight = height ~/ 2;
    int uvIndex = ySize;
    
    for (int y = 0; y < uvHeight; y++) {
      for (int x = 0; x < uvWidth; x++) {
        final int vIdx = y * vPlane.bytesPerRow + x * (vPlane.bytesPerPixel ?? 1);
        final int uIdx = y * uPlane.bytesPerRow + x * (uPlane.bytesPerPixel ?? 1);
        
        if (vIdx < vPlane.bytes.length && uIdx < uPlane.bytes.length) {
          nv21[uvIndex++] = vPlane.bytes[vIdx];
          nv21[uvIndex++] = uPlane.bytes[uIdx];
        }
      }
    }
    
    return nv21;
  }
  
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
    debugPrint('TextRecognitionService disposed');
  }
}

/// Represents a recognized text block
class RecognizedTextBlock {
  final String text;
  final double relativeSize;
  final String position;
  
  RecognizedTextBlock({
    required this.text,
    required this.relativeSize,
    required this.position,
  });
  
  @override
  String toString() => '$text ($position)';
}
