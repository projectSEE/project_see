import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/ml_kit_service.dart';
import '../services/tts_service.dart';
import '../services/vibration_service.dart';
import '../services/gemini_service.dart';
import '../services/gemini_live_service.dart';
import '../services/audio_stream_service.dart';
import '../services/audio_player_service.dart';
import '../services/image_stream_service.dart';
import '../services/unified_media_stream_service.dart';
import '../services/text_recognition_service.dart';
import '../services/image_labeling_service.dart';
import '../services/context_aggregator_service.dart';
import '../services/depth_estimation_service.dart';
import '../models/obstacle_info.dart';
import '../widgets/camera_preview.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'navigation_screen.dart';

/// Main screen for obstacle detection
class ObstacleDetectorScreen extends StatefulWidget {
  const ObstacleDetectorScreen({super.key});

  @override
  State<ObstacleDetectorScreen> createState() => _ObstacleDetectorScreenState();
}

class _ObstacleDetectorScreenState extends State<ObstacleDetectorScreen>
    with WidgetsBindingObserver {
  // Camera
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  CameraDescription? _selectedCamera;
  
  // Services
  final MLKitService _mlKitService = MLKitService();
  final TTSService _ttsService = TTSService();
  final VibrationService _vibrationService = VibrationService();
  final GeminiService _geminiService = GeminiService();
  final GeminiLiveService _geminiLiveService = GeminiLiveService();
  final AudioStreamService _audioStreamService = AudioStreamService();
  final AudioPlayerService _audioPlayerService = AudioPlayerService();
  final ImageStreamService _imageStreamService = ImageStreamService();
  final UnifiedMediaStreamService _unifiedMediaService = UnifiedMediaStreamService();
  
  // New ML Kit Services for enhanced context
  final TextRecognitionService _textRecognitionService = TextRecognitionService();
  final ImageLabelingService _imageLabelingService = ImageLabelingService();
  final ContextAggregatorService _contextAggregator = ContextAggregatorService();
  
  // Depth Anything V2 Estimation
  final DepthEstimationService _depthService = DepthEstimationService();
  bool _depthModelLoaded = false;
  
  // State
  bool _isInitialized = false;
  bool _isDetecting = true;
  bool _hasPermission = false;
  bool _useStreamMode = true; // Try stream mode first
  bool _isLiveMode = false;
  bool _isListening = false;
  List<DetectedObstacle> _obstacles = [];
  List<DetectedLabel> _detectedLabels = [];  // For UI display
  List<RecognizedTextBlock> _recognizedTexts = [];  // For UI display
  String _statusMessage = 'Initializing...';
  Timer? _announceTimer;
  Timer? _fallbackTimer;
  Timer? _liveFrameTimer;
  int _streamErrorCount = 0;
  
  // Speech recognition
  late stt.SpeechToText _speech;
  String _spokenText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _announceTimer?.cancel();
    _fallbackTimer?.cancel();
    _cameraController?.dispose();
    _mlKitService.dispose();
    _ttsService.dispose();
    _vibrationService.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _fallbackTimer?.cancel();
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeApp() async {
    final cameraStatus = await Permission.camera.request();
    
    if (cameraStatus.isGranted) {
      setState(() {
        _hasPermission = true;
        _statusMessage = 'Initializing services...';
      });
      
      await _mlKitService.initialize();
      await _ttsService.initialize();
      await _vibrationService.initialize();
      await _geminiService.initialize();
      
      // Initialize new ML Kit services for enhanced context
      await _textRecognitionService.initialize();
      await _imageLabelingService.initialize();
      
      // Initialize Depth Anything V2 depth estimation (non-blocking)
      _depthService.initialize().then((success) {
        if (mounted) {
          setState(() => _depthModelLoaded = success);
          if (success) {
            debugPrint('🧠 Depth Anything V2 ready');
          }
        }
      });
      
      // Initialize speech recognition
      _speech = stt.SpeechToText();
      await _speech.initialize();
      
      // Request microphone permission
      await Permission.microphone.request();
      
      await _initializeCamera();
      
      // Start periodic announcement timer
      _announceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_isDetecting && _obstacles.isNotEmpty) {
          _announceClosestObstacle();
        }
      });
      
      await _ttsService.speak('Obstacle detector ready. Point camera forward.');
    } else {
      setState(() => _statusMessage = 'Camera permission required');
    }
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    
    if (_cameras.isEmpty) {
      setState(() => _statusMessage = 'No camera found');
      return;
    }
    
    _selectedCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    
    _cameraController = CameraController(
      _selectedCamera!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    
    try {
      await _cameraController!.initialize();
      
      if (_useStreamMode) {
        // Try stream-based detection
        await _cameraController!.startImageStream(_processStreamImage);
      } else {
        // Use fallback file-based detection
        _startFallbackDetection();
      }
      
      setState(() {
        _isInitialized = true;
        _statusMessage = 'Ready';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Camera error: $e');
    }
  }

  void _processStreamImage(CameraImage image) async {
    if (!_isDetecting || _selectedCamera == null) return;
    
    // If in Live mode, add video frames to unified stream
    if (_isLiveMode && _unifiedMediaService.isActive) {
      // Don't await - let it run in background
      _unifiedMediaService.processCameraFrame(image).catchError((e) {
        debugPrint('❌ processCameraFrame error: $e');
      });
    }
    
    // Run all ML Kit APIs in parallel
    final obstaclesFuture = _mlKitService.processImage(image, _selectedCamera!);
    final textFuture = _textRecognitionService.processImage(image, _selectedCamera!);
    final labelsFuture = _imageLabelingService.processImage(image, _selectedCamera!);
    
    // Wait for obstacle detection (primary)
    final obstacles = await obstaclesFuture;
    
    // Check for repeated errors
    if (obstacles.isEmpty && _mlKitService.isProcessing == false) {
      _streamErrorCount++;
      if (_streamErrorCount > 100) {
        // Switch to fallback mode
        debugPrint('⚠️ Stream mode failing, switching to file-based mode');
        _switchToFallbackMode();
      }
    } else {
      _streamErrorCount = 0;
    }
    
    if (mounted && obstacles.isNotEmpty) {
      setState(() {
        _obstacles = obstacles;
      });
      
      // Find closest obstacle by bounding box size
      final closest = obstacles.reduce((a, b) => 
        a.relativeSize > b.relativeSize ? a : b);
      
      // Try to get accurate depth from Depth Anything V2 if available
      double proximity = closest.relativeSize;
      bool isApproaching = false;
      bool isDanger = false;
      String? trend;
      
      if (_depthModelLoaded && _depthService.isInitialized) {
        // Get depth at center of bounding box with temporal tracking
        final normalizedX = (closest.boundingBox.center.dx / image.width).clamp(0.0, 1.0);
        final normalizedY = (closest.boundingBox.center.dy / image.height).clamp(0.0, 1.0);
        
        final depthChangeResult = await _depthService.estimateDepthWithTrend(
          image,
          normalizedX,
          normalizedY,
          closest.label,  // Track by object label
        );
        
        if (depthChangeResult != null) {
          proximity = depthChangeResult.current.normalizedDepth;
          isApproaching = depthChangeResult.isApproaching;
          isDanger = depthChangeResult.isDanger;
          trend = depthChangeResult.trend;
          
          debugPrint('🧠 Depth: ${closest.label} - ${depthChangeResult.fullDescription}');
          
          // Extra warning if approaching
          if (isDanger) {
            debugPrint('⚠️ DANGER: ${closest.label} is approaching fast and close!');
          }
        }
      }
      
      debugPrint('🎯 Closest obstacle: ${closest.label}, proximity=${(proximity * 100).toStringAsFixed(1)}%, trend=$trend');
      
      // Vibrate based on proximity - stronger if approaching
      await _vibrationService.vibrateForProximity(proximity, intensityBoost: isApproaching ? 0.2 : 0.0);
    }
    
    // Process text and labels for context (non-blocking)
    _processEnhancedContext(obstacles, textFuture, labelsFuture);
  }

  /// Process enhanced context from Text Recognition and Image Labeling
  Future<void> _processEnhancedContext(
    List<DetectedObstacle> obstacles,
    Future<List<RecognizedTextBlock>> textFuture,
    Future<List<DetectedLabel>> labelsFuture,
  ) async {
    try {
      // Wait for text and labels (with timeout)
      final textBlocks = await textFuture.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => <RecognizedTextBlock>[],
      );
      
      final labels = await labelsFuture.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => <DetectedLabel>[],
      );
      
      // ALWAYS log what we detect (for debugging)
      if (textBlocks.isNotEmpty) {
        debugPrint('📖 Text detected: ${textBlocks.map((t) => t.text).join(", ")}');
      }
      if (labels.isNotEmpty) {
        debugPrint('🏷️ Labels: ${labels.map((l) => l.label).join(", ")}');
      }
      
      // Update UI state with detected labels and texts
      if (mounted && (labels.isNotEmpty || textBlocks.isNotEmpty)) {
        setState(() {
          _detectedLabels = labels;
          _recognizedTexts = textBlocks;
        });
      }
      
      // Only process context updates at intervals
      if (!_contextAggregator.shouldUpdate()) return;
      
      // Convert obstacles to ObstacleInfo for context aggregator
      final obstacleInfos = obstacles.map((o) => ObstacleInfo(
        label: o.label,
        position: o.position,
        relativeSize: o.relativeSize,
      )).toList();
      
      // Aggregate all context
      final context = _contextAggregator.aggregate(
        obstacles: obstacleInfos,
        textBlocks: textBlocks,
        labels: labels,
      );
      
      // Announce important text immediately
      for (final text in textBlocks) {
        if (_textRecognitionService.isNewText(text.text)) {
          await _ttsService.speak('Text: ${text.text}');
          break; // Only announce one text at a time
        }
      }
      
      // Mark as updated
      _contextAggregator.markUpdated(context.summary);
      
    } catch (e) {
      debugPrint('❌ Enhanced context error: $e');
    }
  }

  void _switchToFallbackMode() async {
    _useStreamMode = false;
    await _cameraController?.stopImageStream();
    _startFallbackDetection();
  }

  void _startFallbackDetection() {
    _fallbackTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_isDetecting && _isInitialized && !_mlKitService.isProcessing) {
        await _captureAndDetect();
      }
    });
  }

  Future<void> _captureAndDetect() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final obstacles = await _mlKitService.processImageFile(imageFile.path);
      
      try {
        await File(imageFile.path).delete();
      } catch (_) {}
      
      if (mounted) {
        setState(() {
          _obstacles = obstacles;
        });
        
        if (obstacles.isNotEmpty) {
          final closest = obstacles.reduce((a, b) => 
            a.relativeSize > b.relativeSize ? a : b);
          await _vibrationService.vibrateForProximity(closest.relativeSize);
        }
      }
    } catch (e) {
      debugPrint('Error in capture: $e');
    }
  }

  void _announceClosestObstacle() async {
    if (_obstacles.isEmpty) return;
    
    final closest = _obstacles.reduce((a, b) => 
      a.relativeSize > b.relativeSize ? a : b);
    
    if (closest.isVeryClose) {
      await _ttsService.speakUrgent('Warning! ${closest.description}');
    } else if (closest.isClose) {
      await _ttsService.speak(closest.description);
    }
  }

  void _toggleDetection() {
    setState(() {
      _isDetecting = !_isDetecting;
      _statusMessage = _isDetecting ? 'Detecting...' : 'Paused';
      if (!_isDetecting) {
        _obstacles = [];
      }
    });
    
    _ttsService.speak(_isDetecting ? 'Detection resumed' : 'Detection paused');
    
    if (!_isDetecting) {
      _vibrationService.cancel();
    }
  }

  /// Capture image and describe scene using Gemini AI
  Future<void> _describeScene() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _ttsService.speak('Camera not ready');
      return;
    }
    
    if (_geminiService.isProcessing) {
      await _ttsService.speak('Still analyzing...');
      return;
    }
    
    if (!_geminiService.isInitialized) {
      await _ttsService.speak('Gemini AI not initialized. Please set your API key.');
      return;
    }
    
    await _ttsService.speak('Analyzing scene...');
    
    try {
      // Pause detection during capture
      final wasDetecting = _isDetecting;
      if (wasDetecting && _useStreamMode) {
        await _cameraController!.stopImageStream();
      }
      
      // Capture image
      final XFile imageFile = await _cameraController!.takePicture();
      
      // Get description from Gemini
      final description = await _geminiService.describeScene(imageFile.path);
      
      // Speak the description
      await _ttsService.speak(description);
      
      // Delete temp file
      try {
        await File(imageFile.path).delete();
      } catch (_) {}
      
      // Resume detection
      if (wasDetecting && _useStreamMode) {
        await _cameraController!.startImageStream(_processStreamImage);
      }
    } catch (e) {
      debugPrint('❌ Describe scene error: $e');
      await _ttsService.speak('Error analyzing scene');
    }
  }

  /// Toggle Live mode on/off - connects to Gemini Live API
  Future<void> _toggleLiveMode() async {
    if (!_isLiveMode) {
      // Start Live mode
      setState(() {
        _isLiveMode = true;
        _statusMessage = 'Connecting to Gemini Live...';
      });
      
      await _ttsService.speak('连接 Gemini Live...');
      
      // Initialize services
      await _geminiLiveService.initialize();
      await _audioPlayerService.initialize();
      
      // Set up callbacks - now Gemini returns AUDIO directly!
      _geminiLiveService.onAudioResponse = (audioData) {
        // Play Gemini's voice directly
        _audioPlayerService.queueAudio(audioData);
      };
      
      _geminiLiveService.onResponse = (text) {
        // Fallback: if text is returned, use TTS
        debugPrint('📝 Text fallback: $text');
        _ttsService.speak(text);
      };
      
      _geminiLiveService.onError = (error) {
        _ttsService.speak('错误: $error');
      };
      
      // Set up onReady callback - triggered when SetupComplete is received
      _geminiLiveService.onReady = () async {
        debugPrint('🚀 Gemini ready - starting unified audio/video streaming');
        
        // Send initial image to trigger a response
        await Future.delayed(const Duration(milliseconds: 300));
        await _sendFrameToLive();
        _geminiLiveService.sendText('Describe what you see briefly. What is in front of me?');
        
        // Wait a bit for the response to start
        await Future.delayed(const Duration(seconds: 1));
        
        // Start unified media stream (audio + video combined!)
        _unifiedMediaService.start(); // 1 FPS video as recommended
        
        // Connect unified stream to Gemini
        if (_unifiedMediaService.mediaStream != null) {
          _geminiLiveService.sendMediaStream(_unifiedMediaService.mediaStream!);
          debugPrint('📹 Unified audio+video stream connected to Gemini');
        }
        
        // Start microphone and feed to unified stream
        final audioStream = await _audioStreamService.startRecordingStream();
        if (audioStream != null) {
          audioStream.listen((audioData) {
            _unifiedMediaService.addAudio(audioData);
          });
          debugPrint('🎤 Audio feeding to unified stream');
        }
        
        debugPrint('✅ Live mode started with unified A/V stream!');
      };
      
      await _geminiLiveService.connect();
      
      if (_geminiLiveService.isConnected) {
        await _ttsService.speak('Live mode connected! I can now see and hear you.');
        
        setState(() {
          _statusMessage = 'Live mode active';
        });
      } else {
        setState(() {
          _isLiveMode = false;
          _statusMessage = 'Failed to connect';
        });
        await _ttsService.speak('Failed to connect. Please try again.');
      }
    } else {
      // Stop Live mode
      _unifiedMediaService.stop();
      _liveFrameTimer?.cancel();
      _liveFrameTimer = null;
      await _audioStreamService.stopRecording();
      await _audioPlayerService.stop();
      await _geminiLiveService.disconnect();
      
      setState(() {
        _isLiveMode = false;
        _statusMessage = _isDetecting ? 'Real-time detection' : 'Paused';
      });
      
      await _ttsService.speak('Live mode stopped.');
    }
  }

  /// Send current camera frame to Gemini Live
  Future<void> _sendFrameToLive() async {
    if (!_isLiveMode || _cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    try {
      // Capture current frame
      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List imageBytes = await File(imageFile.path).readAsBytes();
      
      // Compress image for faster transmission (reduce quality to ~50KB)
      // Since image package is complex, we'll just send as-is for now
      // and rely on the frame size being manageable
      
      // Send to Gemini Live
      await _geminiLiveService.sendImage(imageBytes);
      
      // Clean up
      try {
        await File(imageFile.path).delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ Send frame error: $e');
    }
  }

  /// Start listening for voice input
  void _startListening() async {
    if (!_speech.isAvailable) {
      await _ttsService.speak('Speech recognition not available');
      return;
    }
    
    setState(() => _isListening = true);
    _spokenText = '';
    
    await _speech.listen(
      onResult: (result) {
        _spokenText = result.recognizedWords;
        debugPrint('🎤 Heard: $_spokenText');
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
    );
  }

  /// Stop listening and ask Gemini
  Future<void> _stopListeningAndAsk() async {
    await _speech.stop();
    setState(() => _isListening = false);
    
    if (_spokenText.isEmpty) {
      await _ttsService.speak('I did not hear anything. Try again.');
      return;
    }
    
    await _ttsService.speak('You asked: $_spokenText. Analyzing...');
    
    try {
      // Pause detection during capture
      final wasDetecting = _isDetecting;
      if (wasDetecting && _useStreamMode) {
        await _cameraController!.stopImageStream();
      }
      
      // Capture image
      final XFile imageFile = await _cameraController!.takePicture();
      
      // Get answer from Gemini
      final answer = await _geminiService.askQuestion(imageFile.path, _spokenText);
      
      // Speak the answer
      await _ttsService.speak(answer);
      
      // Delete temp file
      try {
        await File(imageFile.path).delete();
      } catch (_) {}
      
      // Resume detection
      if (wasDetecting && _useStreamMode) {
        await _cameraController!.startImageStream(_processStreamImage);
      }
    } catch (e) {
      debugPrint('❌ Ask Gemini error: $e');
      await _ttsService.speak('Error processing your question');
    }
  }

  /// Test depth estimation manually - actually runs inference
  Future<void> _testDepthEstimation() async {
    debugPrint('🧪 ========== DEPTH TEST START ==========');
    
    if (!_depthModelLoaded || !_depthService.isInitialized) {
      debugPrint('❌ Depth model not loaded! Trying to initialize...');
      debugPrint('   _depthModelLoaded: $_depthModelLoaded');
      debugPrint('   _depthService.isInitialized: ${_depthService.isInitialized}');
      
      // Force try to initialize
      final success = await _depthService.initialize();
      if (success) {
        debugPrint('✅ Manual initialization succeeded!');
        setState(() => _depthModelLoaded = true);
      } else {
        debugPrint('❌ Manual initialization also failed!');
        await _ttsService.speak('Depth model failed to load');
        return;
      }
    }
    
    debugPrint('✅ Depth model is loaded');
    
    if (_cameraController == null) {
      debugPrint('❌ Camera not available');
      await _ttsService.speak('Camera not available');
      return;
    }
    
    // Temporarily stop streaming to capture a frame
    final wasStreaming = _cameraController!.value.isStreamingImages;
    if (wasStreaming) {
      await _cameraController!.stopImageStream();
    }
    
    try {
      // Start streaming and capture one frame for testing
      CameraImage? testFrame;
      final completer = Completer<void>();
      
      await _cameraController!.startImageStream((image) async {
        if (testFrame == null) {
          testFrame = image;
          completer.complete();
        }
      });
      
      // Wait for a frame (max 2 seconds)
      await completer.future.timeout(const Duration(seconds: 2));
      await _cameraController!.stopImageStream();
      
      if (testFrame == null) {
        debugPrint('❌ Failed to capture test frame');
        await _ttsService.speak('Failed to capture frame');
        return;
      }
      
      debugPrint('📷 Captured frame: ${testFrame!.width}x${testFrame!.height}');
      
      // Run depth estimation at center of frame
      debugPrint('🔄 Running depth inference...');
      final depthResult = await _depthService.estimateDepthAtPoint(
        testFrame!,
        0.5, // center X
        0.5, // center Y
      );
      
      if (depthResult != null) {
        debugPrint('🎉 ========== DEPTH RESULT ==========');
        debugPrint('   Raw depth: ${depthResult.rawDepth.toStringAsFixed(2)}');
        debugPrint('   Normalized: ${(depthResult.normalizedDepth * 100).toStringAsFixed(1)}%');
        debugPrint('   Category: ${depthResult.distanceCategory}');
        debugPrint('=====================================');
        
        await _ttsService.speak('Depth test success! ${depthResult.distanceCategory}');
        
        setState(() {
          _statusMessage = 'Depth: ${depthResult.description}';
        });
      } else {
        debugPrint('❌ Depth estimation returned null');
        await _ttsService.speak('Depth estimation failed');
      }
      
    } catch (e) {
      debugPrint('❌ Depth test error: $e');
      await _ttsService.speak('Depth test error');
    } finally {
      // Restore streaming if it was running
      if (wasStreaming && mounted) {
        await _cameraController!.startImageStream(_processStreamImage);
      }
    }
    
    debugPrint('🧪 ========== DEPTH TEST END ==========');
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _hasPermission ? _buildMainContent() : _buildPermissionRequest(),
      ),
    );
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt, size: 80, color: Colors.white54),
            const SizedBox(height: 24),
            const Text(
              'Camera Permission Required',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'This app needs camera access to detect obstacles.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => openAppSettings(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Open Settings', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        Expanded(
          child: _isInitialized && _cameraController != null
              ? Stack(
                  children: [
                    CameraPreviewWidget(
                      controller: _cameraController!,
                      obstacles: _obstacles,
                    ),
                    // Labels and Text overlay
                    _buildLabelsOverlay(),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(_statusMessage, style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
        ),
        _buildControlPanel(),
      ],
    );
  }
  
  /// Build overlay showing detected labels and text
  Widget _buildLabelsOverlay() {
    if (_detectedLabels.isEmpty && _recognizedTexts.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image Labels
            if (_detectedLabels.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.label, color: Colors.greenAccent, size: 18),
                  const SizedBox(width: 8),
                  const Text('Labels:', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _detectedLabels.take(5).map((label) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                  ),
                  child: Text(
                    '${label.label} (${(label.confidence * 100).toStringAsFixed(0)}%)',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                )).toList(),
              ),
            ],
            // Recognized Text
            if (_recognizedTexts.isNotEmpty) ...[
              if (_detectedLabels.isNotEmpty) const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.text_fields, color: Colors.cyanAccent, size: 18),
                  const SizedBox(width: 8),
                  const Text('Text:', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              ...(_recognizedTexts.take(3).map((text) => Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(
                  '"${text.text}" (${text.position})',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status indicator row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isDetecting ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isDetecting 
                    ? (_useStreamMode ? 'Real-time detection' : 'Detection active')
                    : 'Detection paused',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                if (_obstacles.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_obstacles.length} obstacle${_obstacles.length > 1 ? 's' : ''}',
                      style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            
            // Secondary buttons row (Pause + Describe)
            Row(
              children: [
                // Pause/Resume button
                Expanded(
                  child: Semantics(
                    button: true,
                    label: _isDetecting ? 'Pause detection' : 'Resume detection',
                    child: GestureDetector(
                      onTap: _toggleDetection,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: _isDetecting ? Colors.red[700] : Colors.green[700],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_isDetecting ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                _isDetecting ? 'PAUSE' : 'RESUME',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Describe Scene button
                Expanded(
                  child: GestureDetector(
                    onTap: _describeScene,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.purple[700],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('DESCRIBE', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Depth Test button
            GestureDetector(
              onTap: _testDepthEstimation,
              child: Container(
                width: double.infinity,
                height: 40,
                decoration: BoxDecoration(
                  color: _depthModelLoaded ? Colors.cyan[700] : Colors.grey[600],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_depthModelLoaded ? Icons.check_circle : Icons.error, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _depthModelLoaded ? 'DEPTH TEST (Ready)' : 'DEPTH TEST (Not Loaded)',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Primary LIVE button - prominent
            GestureDetector(
              onTap: _toggleLiveMode,
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  gradient: _isLiveMode 
                    ? const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFFF5252)])
                    : const LinearGradient(colors: [Color(0xFF1976D2), Color(0xFF42A5F5)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _isLiveMode ? Colors.red.withOpacity(0.4) : Colors.blue.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLiveMode) ...[
                        Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'END LIVE',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mic, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ] else ...[
                        const Icon(Icons.videocam, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'START LIVE ASSISTANT',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Navigation button
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NavigationScreen()),
                );
              },
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.teal[600],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.navigation, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Text('NAVIGATE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
