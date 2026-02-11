import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Service for labeling objects in camera frames
/// Provides more specific object identification than basic object detection
class ImageLabelingService {
  ImageLabeler? _imageLabeler;
  bool _isProcessing = false;
  
  // Cache to avoid repetitive announcements
  List<String> _lastLabels = [];
  DateTime _lastLabelTime = DateTime.now();
  
  bool get isProcessing => _isProcessing;
  
  /// Initialize the image labeler
  Future<void> initialize() async {
    final options = ImageLabelerOptions(confidenceThreshold: 0.6);
    _imageLabeler = ImageLabeler(options: options);
    debugPrint('✅ ImageLabelingService initialized');
  }
  
  /// Process a camera image and get labels
  Future<List<DetectedLabel>> processImage(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_isProcessing || _imageLabeler == null) return [];
    
    _isProcessing = true;
    
    try {
      final inputImage = _buildInputImage(image, camera);
      if (inputImage == null) {
        _isProcessing = false;
        return [];
      }
      
      final labels = await _imageLabeler!.processImage(inputImage);
      
      // Convert to our model and filter
      final results = labels
          .where((label) => label.confidence > 0.6)
          .take(5) // Top 5 labels
          .map((label) => DetectedLabel(
                label: label.label,
                confidence: label.confidence,
              ))
          .toList();
      
      _isProcessing = false;
      return results;
      
    } catch (e) {
      debugPrint('❌ Image labeling error: $e');
      _isProcessing = false;
      return [];
    }
  }
  
  /// Check if labels are significantly different from last detection
  bool hasNewLabels(List<DetectedLabel> labels) {
    if (labels.isEmpty) return false;
    
    final now = DateTime.now();
    final timeSinceLast = now.difference(_lastLabelTime);
    
    // Always announce if more than 5 seconds
    if (timeSinceLast.inSeconds > 5) {
      _updateCache(labels);
      return true;
    }
    
    // Check if labels are different
    final currentLabels = labels.map((l) => l.label).toList();
    final isDifferent = currentLabels.any((l) => !_lastLabels.contains(l));
    
    if (isDifferent) {
      _updateCache(labels);
      return true;
    }
    
    return false;
  }
  
  void _updateCache(List<DetectedLabel> labels) {
    _lastLabels = labels.map((l) => l.label).toList();
    _lastLabelTime = DateTime.now();
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
    _imageLabeler?.close();
    _imageLabeler = null;
    debugPrint('ImageLabelingService disposed');
  }
}

/// Represents a detected image label
class DetectedLabel {
  final String label;
  final double confidence;
  
  DetectedLabel({
    required this.label,
    required this.confidence,
  });
  
  @override
  String toString() => '$label (${(confidence * 100).toStringAsFixed(0)}%)';
}
