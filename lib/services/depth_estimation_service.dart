import 'dart:typed_data';
import 'dart:collection';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Result from depth estimation
class DepthResult {
  final double rawDepth;
  final double normalizedDepth; // 0.0 (far) to 1.0 (close)
  final String distanceCategory;
  
  DepthResult({
    required this.rawDepth,
    required this.normalizedDepth,
    required this.distanceCategory,
  });
  
  String get description => '$distanceCategory (${(normalizedDepth * 100).toStringAsFixed(0)}%)';
}

/// Depth sample with timestamp for temporal tracking
class DepthSample {
  final double normalizedDepth;
  final DateTime timestamp;
  
  DepthSample(this.normalizedDepth, this.timestamp);
}

/// Result with temporal change detection
class DepthChangeResult {
  final DepthResult current;
  final double? changeRate;     // Change per second (positive = approaching)
  final String trend;           // 'approaching_fast', 'approaching', 'stationary', 'moving_away', 'moving_away_fast'
  final bool isApproaching;
  final bool isDanger;          // Fast approaching AND close
  
  DepthChangeResult({
    required this.current,
    this.changeRate,
    required this.trend,
    required this.isApproaching,
    required this.isDanger,
  });
  
  String get trendDescription {
    switch (trend) {
      case 'approaching_fast': return '快速靠近';
      case 'approaching': return '正在靠近';
      case 'stationary': return '静止';
      case 'moving_away': return '正在远离';
      case 'moving_away_fast': return '快速远离';
      default: return '';
    }
  }
  
  String get fullDescription => '${current.description} ${trendDescription}';
}

/// Depth estimation service using Depth Anything V2 with ONNX Runtime
class DepthEstimationService {
  static const String modelPath = 'assets/models/depth_anything_v2.onnx';
  static const int inputSize = 252;  // Must be multiple of 14 (ViT patch size). 252 = 18*14
  static const int outputSize = 252; // Same as input for opset 17 model
  
  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  bool _isInitialized = false;
  bool _isProcessing = false;
  
  // Throttling
  DateTime _lastProcessTime = DateTime.now();
  final Duration _minInterval = const Duration(milliseconds: 333); // Max 3 FPS
  DepthResult? _cachedResult;
  
  // Temporal depth tracking - stores history per object label
  final Map<String, Queue<DepthSample>> _depthHistory = {};
  static const int _maxHistorySamples = 5;           // Keep last 5 samples
  static const double _approachingThreshold = 0.05;  // 5% per second = approaching
  static const double _fastThreshold = 0.15;         // 15% per second = fast
  
  bool get isInitialized => _isInitialized;
  
  /// Initialize the ONNX Runtime session
  Future<bool> initialize() async {
    try {
      debugPrint('🧠 [Step 1] Starting Depth Anything V2 initialization...');
      
      // Initialize ONNX Runtime environment
      debugPrint('🧠 [Step 2] Initializing OrtEnv...');
      OrtEnv.instance.init();
      debugPrint('🧠 [Step 2] OrtEnv initialized');
      
      // Create session options
      debugPrint('🧠 [Step 3] Creating OrtSessionOptions...');
      _sessionOptions = OrtSessionOptions();
      debugPrint('🧠 [Step 3] OrtSessionOptions created');
      
      // Load model from assets
      debugPrint('🧠 [Step 4] Loading model from assets: $modelPath');
      final rawAssetFile = await rootBundle.load(modelPath);
      final bytes = rawAssetFile.buffer.asUint8List();
      debugPrint('🧠 [Step 4] Model loaded: ${bytes.length} bytes');
      
      // Create session from buffer
      debugPrint('🧠 [Step 5] Creating OrtSession from buffer...');
      _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
      debugPrint('🧠 [Step 5] OrtSession created');
      
      _isInitialized = true;
      debugPrint('✅ Depth Anything V2 model loaded successfully');
      debugPrint('   Model: $modelPath');
      
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to load Depth Anything V2 model: $e');
      debugPrint('   Stack trace: $stackTrace');
      debugPrint('   Make sure depth_anything_v2.onnx is in assets/models/');
      _isInitialized = false;
      return false;
    }
  }
  
  /// Estimate depth at a specific point
  Future<DepthResult?> estimateDepthAtPoint(
    CameraImage image,
    double normalizedX, // 0.0 to 1.0
    double normalizedY, // 0.0 to 1.0
  ) async {
    if (!_isInitialized || _session == null || _isProcessing) {
      return _cachedResult; // Return cached result while processing
    }
    
    // Throttle: return cached result if called too frequently
    final now = DateTime.now();
    if (now.difference(_lastProcessTime) < _minInterval) {
      return _cachedResult;
    }
    _lastProcessTime = now;
    
    _isProcessing = true;
    
    try {
      // Convert camera image to RGB bytes
      final rgbBytes = await _convertCameraImageToRgb(image);
      if (rgbBytes == null) {
        _isProcessing = false;
        return null;
      }
      
      // Preprocess: resize to 252x252 and convert to float32 NCHW format
      final inputData = _preprocessImageFloat32(rgbBytes, image.width, image.height);
      
      // Create input tensor (NCHW format: [1, 3, 252, 252])
      final shape = [1, 3, inputSize, inputSize];
      final inputTensor = OrtValueTensor.createTensorWithDataList(inputData, shape);
      
      debugPrint('🔧 Created float32 tensor with shape: $shape');
      
      // Run inference
      final inputs = {'input': inputTensor};
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);
      
      // Release input resources
      inputTensor.release();
      runOptions.release();
      
      if (outputs == null || outputs.isEmpty) {
        _isProcessing = false;
        return null;
      }
      
      // Get output tensor
      final outputTensor = outputs.first;
      if (outputTensor == null) {
        _isProcessing = false;
        return null;
      }
      
      // Extract depth data
      final outputData = outputTensor.value as List;
      final depthMap = _extractDepthMap(outputData);
      
      // Release output resources
      for (var output in outputs) {
        output?.release();
      }
      
      // Get depth at point
      final x = (normalizedX * outputSize).clamp(0, outputSize - 1).toInt();
      final y = (normalizedY * outputSize).clamp(0, outputSize - 1).toInt();
      
      final depthValue = depthMap[y][x];
      
      // Normalize depth (higher = closer in Depth Anything)
      final normalizedDepth = _normalizeDepth(depthMap, depthValue);
      
      _isProcessing = false;
      
      final result = DepthResult(
        rawDepth: depthValue,
        normalizedDepth: normalizedDepth,
        distanceCategory: _categorizeDistance(normalizedDepth),
      );
      _cachedResult = result;
      return result;
      
    } catch (e) {
      debugPrint('❌ Depth estimation error: $e');
      _isProcessing = false;
      return null;
    }
  }
  
  /// Convert YUV420 camera image to RGB bytes
  Future<Uint8List?> _convertCameraImageToRgb(CameraImage image) async {
    try {
      if (image.format.group != ImageFormatGroup.yuv420) {
        debugPrint('⚠️ Unsupported image format');
        return null;
      }
      
      final int width = image.width;
      final int height = image.height;
      final rgbBytes = Uint8List(width * height * 3);
      
      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes[1].bytes;
      final vPlane = image.planes[2].bytes;
      
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
      
      int rgbIndex = 0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * image.planes[0].bytesPerRow + x;
          final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
          
          final int yValue = yPlane[yIndex];
          final int uValue = uPlane[uvIndex];
          final int vValue = vPlane[uvIndex];
          
          // YUV to RGB conversion
          int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
          int g = (yValue - 0.344 * (uValue - 128) - 0.714 * (vValue - 128)).round().clamp(0, 255);
          int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);
          
          rgbBytes[rgbIndex++] = r;
          rgbBytes[rgbIndex++] = g;
          rgbBytes[rgbIndex++] = b;
        }
      }
      
      return rgbBytes;
    } catch (e) {
      debugPrint('❌ Image conversion error: $e');
      return null;
    }
  }
  
  /// Preprocess image for Depth Anything V2 (float32 NCHW model)
  Float32List _preprocessImageFloat32(Uint8List rgbBytes, int width, int height) {
    // Create float32 input tensor [1, 3, 252, 252] - NCHW format
    // Model expects normalized float values 0.0-1.0
    final inputData = Float32List(1 * 3 * inputSize * inputSize);
    
    // Resize and convert to NCHW format (batch, channels, height, width)
    // Channel order: R, G, B (all R values, then all G, then all B)
    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          // Sample from source
          final srcX = (x * width / inputSize).round().clamp(0, width - 1);
          final srcY = (y * height / inputSize).round().clamp(0, height - 1);
          
          final pixelIndex = (srcY * width + srcX) * 3;
          
          // NCHW format: all channel c values in sequence
          final outputIndex = (c * inputSize * inputSize) + (y * inputSize) + x;
          
          // Normalize to 0.0-1.0
          inputData[outputIndex] = rgbBytes[pixelIndex + c] / 255.0;
        }
      }
    }
    
    return inputData;
  }
  
  /// Extract 2D depth map from model output
  List<List<double>> _extractDepthMap(List<dynamic> output) {
    final depthMap = <List<double>>[];
    
    // Flatten nested lists if needed
    List<dynamic> flatData = output;
    while (flatData.isNotEmpty && flatData[0] is List) {
      flatData = (flatData as List).expand((e) => e is List ? e : [e]).toList();
    }
    
    // Reshape to 2D
    for (int y = 0; y < outputSize; y++) {
      final row = <double>[];
      for (int x = 0; x < outputSize; x++) {
        final idx = y * outputSize + x;
        if (idx < flatData.length) {
          row.add((flatData[idx] as num).toDouble());
        } else {
          row.add(0.0);
        }
      }
      depthMap.add(row);
    }
    
    return depthMap;
  }
  
  /// Normalize depth value relative to the depth map
  double _normalizeDepth(List<List<double>> depthMap, double value) {
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    
    for (var row in depthMap) {
      for (var v in row) {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }
    }
    
    if (maxVal == minVal) return 0.5;
    
    // In Depth Anything, higher values = closer
    return ((value - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);
  }
  
  /// Categorize distance for TTS
  String _categorizeDistance(double normalizedDepth) {
    if (normalizedDepth > 0.7) return 'Very close';
    if (normalizedDepth > 0.5) return 'Close';
    if (normalizedDepth > 0.3) return 'Medium distance';
    return 'Far away';
  }
  
  /// Estimate depth with temporal trend detection
  /// Returns DepthChangeResult with approach/recede information
  Future<DepthChangeResult?> estimateDepthWithTrend(
    CameraImage image,
    double normalizedX,
    double normalizedY,
    String objectLabel,  // Used to track same object across frames
  ) async {
    // Get current depth
    final depthResult = await estimateDepthAtPoint(image, normalizedX, normalizedY);
    if (depthResult == null) return null;
    
    final now = DateTime.now();
    final currentDepth = depthResult.normalizedDepth;
    
    // Get or create history for this object
    if (!_depthHistory.containsKey(objectLabel)) {
      _depthHistory[objectLabel] = Queue<DepthSample>();
    }
    final history = _depthHistory[objectLabel]!;
    
    // Calculate trend from history
    double? changeRate;
    String trend = 'stationary';
    bool isApproaching = false;
    bool isDanger = false;
    
    if (history.isNotEmpty) {
      // Use oldest sample for more stable comparison
      final oldestSample = history.first;
      final timeDelta = now.difference(oldestSample.timestamp).inMilliseconds / 1000.0;
      
      if (timeDelta > 0.1) {  // Need at least 100ms gap
        final depthDelta = currentDepth - oldestSample.normalizedDepth;
        changeRate = depthDelta / timeDelta;
        
        // Determine trend (positive changeRate = getting closer)
        if (changeRate > _fastThreshold) {
          trend = 'approaching_fast';
          isApproaching = true;
        } else if (changeRate > _approachingThreshold) {
          trend = 'approaching';
          isApproaching = true;
        } else if (changeRate < -_fastThreshold) {
          trend = 'moving_away_fast';
        } else if (changeRate < -_approachingThreshold) {
          trend = 'moving_away';
        } else {
          trend = 'stationary';
        }
        
        // Danger = approaching fast AND already close
        isDanger = isApproaching && currentDepth > 0.5;
        
        debugPrint('📊 Depth trend: $objectLabel - $trend (rate: ${(changeRate * 100).toStringAsFixed(1)}%/s)');
      }
    }
    
    // Add current sample to history
    history.addLast(DepthSample(currentDepth, now));
    
    // Keep only recent samples
    while (history.length > _maxHistorySamples) {
      history.removeFirst();
    }
    
    // Clean up old objects not seen recently
    _cleanupOldHistory(now);
    
    return DepthChangeResult(
      current: depthResult,
      changeRate: changeRate,
      trend: trend,
      isApproaching: isApproaching,
      isDanger: isDanger,
    );
  }
  
  /// Remove history for objects not seen in 3 seconds
  void _cleanupOldHistory(DateTime now) {
    final keysToRemove = <String>[];
    
    for (var entry in _depthHistory.entries) {
      if (entry.value.isNotEmpty) {
        final lastSample = entry.value.last;
        if (now.difference(lastSample.timestamp).inSeconds > 3) {
          keysToRemove.add(entry.key);
        }
      }
    }
    
    for (var key in keysToRemove) {
      _depthHistory.remove(key);
    }
  }
  
  /// Clear all depth history
  void clearHistory() {
    _depthHistory.clear();
  }
  
  /// Dispose resources
  void dispose() {
    _session?.release();
    _sessionOptions?.release();
    OrtEnv.instance.release();
    _session = null;
    _isInitialized = false;
  }
}
