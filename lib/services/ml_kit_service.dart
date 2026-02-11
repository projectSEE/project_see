import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

/// Service for ML Kit object detection with real-time stream support
class MLKitService {
  ObjectDetector? _objectDetector;
  bool _isProcessing = false;
  int _frameCount = 0;

  /// Initialize the object detector
  Future<void> initialize() async {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
    debugPrint('✅ ML Kit ObjectDetector initialized (stream mode)');
  }

  /// Process a camera image from stream
  Future<List<DetectedObstacle>> processImage(CameraImage image, CameraDescription camera) async {
    if (_isProcessing || _objectDetector == null) {
      return [];
    }

    _isProcessing = true;
    _frameCount++;

    try {
      final inputImage = _buildInputImage(image, camera);
      if (inputImage == null) {
        _isProcessing = false;
        return [];
      }

      final objects = await _objectDetector!.processImage(inputImage);
      
      // Debug log every 60 frames
      if (_frameCount % 60 == 0) {
        debugPrint('📷 Frame $_frameCount: ${objects.length} objects detected');
      }
      
      if (objects.isEmpty) {
        _isProcessing = false;
        return [];
      }

      final imageWidth = image.width.toDouble();
      final imageHeight = image.height.toDouble();
      final imageArea = imageWidth * imageHeight;

      return objects.map((obj) {
        final centerX = obj.boundingBox.center.dx;
        
        String position;
        if (centerX < imageWidth / 3) {
          position = 'left';
        } else if (centerX > imageWidth * 2 / 3) {
          position = 'right';
        } else {
          position = 'center';
        }

        final objectArea = obj.boundingBox.width * obj.boundingBox.height;
        final relativeSize = objectArea / imageArea;

        String label = 'Object';
        double confidence = 0.5;
        if (obj.labels.isNotEmpty) {
          label = obj.labels.first.text;
          confidence = obj.labels.first.confidence;
        }

        // Debug log the size
        if (_frameCount % 60 == 0) {
          debugPrint('  🎯 $label @ $position, size=${(relativeSize * 100).toStringAsFixed(1)}%');
        }

        return DetectedObstacle(
          label: label,
          position: position,
          relativeSize: relativeSize,
          boundingBox: obj.boundingBox,
          confidence: confidence,
        );
      }).toList();
    } catch (e) {
      if (_frameCount % 60 == 0) {
        debugPrint('❌ Error: $e');
      }
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  /// Process image file (fallback method)
  Future<List<DetectedObstacle>> processImageFile(String imagePath) async {
    if (_isProcessing || _objectDetector == null) {
      return [];
    }

    _isProcessing = true;

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final objects = await _objectDetector!.processImage(inputImage);
      
      debugPrint('📷 File: ${objects.length} objects detected');
      
      if (objects.isEmpty) {
        return [];
      }

      // Get image dimensions
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final imageWidth = frame.image.width.toDouble();
      final imageHeight = frame.image.height.toDouble();
      final imageArea = imageWidth * imageHeight;

      return objects.map((obj) {
        final centerX = obj.boundingBox.center.dx;
        
        String position;
        if (centerX < imageWidth / 3) {
          position = 'left';
        } else if (centerX > imageWidth * 2 / 3) {
          position = 'right';
        } else {
          position = 'center';
        }

        final objectArea = obj.boundingBox.width * obj.boundingBox.height;
        final relativeSize = objectArea / imageArea;

        String label = 'Object';
        if (obj.labels.isNotEmpty) {
          label = obj.labels.first.text;
        }

        return DetectedObstacle(
          label: label,
          position: position,
          relativeSize: relativeSize,
          boundingBox: obj.boundingBox,
          confidence: obj.labels.isNotEmpty ? obj.labels.first.confidence : 0.5,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ Error processing file: $e');
      return [];
    } finally {
      _isProcessing = false;
    }
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

  bool get isProcessing => _isProcessing;

  Future<void> dispose() async {
    await _objectDetector?.close();
    _objectDetector = null;
  }
}

/// Represents a detected obstacle
class DetectedObstacle {
  final String label;
  final String position;
  final double relativeSize;
  final Rect boundingBox;
  final double confidence;

  DetectedObstacle({
    required this.label,
    required this.position,
    required this.relativeSize,
    required this.boundingBox,
    required this.confidence,
  });

  bool get isClose => relativeSize > 0.10;
  bool get isVeryClose => relativeSize > 0.25;

  String get description {
    String distance = isVeryClose ? 'very close' : (isClose ? 'close' : 'ahead');
    return '$label $distance on your $position';
  }
}
