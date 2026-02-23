import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/ml_kit_service.dart';
import '../services/tts_service.dart';
import '../services/vibration_service.dart';
import '../services/gemini_service.dart';
import '../services/text_recognition_service.dart';
import '../services/image_labeling_service.dart';
import '../services/context_aggregator_service.dart';
import '../services/depth_estimation_service.dart';
import '../models/obstacle_info.dart';
import '../widgets/camera_preview.dart';

/// Object Detection Screen — Camera + ML Kit + Depth Estimation
/// Provides real-time obstacle detection with haptic/voice feedback.
class ObjectDetectionScreen extends StatefulWidget {
  const ObjectDetectionScreen({super.key});

  @override
  State<ObjectDetectionScreen> createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen>
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
  final TextRecognitionService _textRecognitionService = TextRecognitionService();
  final ImageLabelingService _imageLabelingService = ImageLabelingService();
  final ContextAggregatorService _contextAggregator = ContextAggregatorService();
  final DepthEstimationService _depthService = DepthEstimationService();
  bool _depthModelLoaded = false;

  // State
  bool _isInitialized = false;
  bool _isDetecting = true;
  bool _hasPermission = false;
  bool _useStreamMode = true;
  bool _isListening = false;
  List<DetectedObstacle> _obstacles = [];
  // ignore: unused_field - populated by _processEnhancedContext
  List<DetectedLabel> _detectedLabels = [];
  // ignore: unused_field - populated by _processEnhancedContext
  List<RecognizedTextBlock> _recognizedTexts = [];
  String _statusMessage = 'Initializing...';
  Timer? _announceTimer;
  Timer? _fallbackTimer;
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

  // ─── INITIALIZATION ─────────────────────────────────────

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
      await _textRecognitionService.initialize();
      await _imageLabelingService.initialize();

      // Initialize Depth Anything V2 (non-blocking)
      _depthService.initialize().then((success) {
        if (mounted) {
          setState(() => _depthModelLoaded = success);
          if (success) debugPrint('🧠 Depth Anything V2 ready');
        }
      });

      // Initialize speech recognition
      _speech = stt.SpeechToText();
      await _speech.initialize();
      await Permission.microphone.request();

      await _initializeCamera();

      // Periodic obstacle announcement
      _announceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_isDetecting && _obstacles.isNotEmpty) {
          _announceClosestObstacle();
        }
      });

      await _ttsService.speak(
        'Object detection ready. Point camera forward. '
        'Double tap to describe scene. Long press to ask a question.',
      );
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
        await _cameraController!.startImageStream(_processStreamImage);
      } else {
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

  // ─── IMAGE PROCESSING ───────────────────────────────────

  void _processStreamImage(CameraImage image) async {
    if (!_isDetecting || _selectedCamera == null) return;

    // Run all ML Kit APIs in parallel
    final obstaclesFuture = _mlKitService.processImage(image, _selectedCamera!);
    final textFuture = _textRecognitionService.processImage(image, _selectedCamera!);
    final labelsFuture = _imageLabelingService.processImage(image, _selectedCamera!);

    final obstacles = await obstaclesFuture;

    // Check for repeated errors
    if (obstacles.isEmpty && _mlKitService.isProcessing == false) {
      _streamErrorCount++;
      if (_streamErrorCount > 100) {
        debugPrint('⚠️ Stream mode failing, switching to file-based mode');
        _switchToFallbackMode();
      }
    } else {
      _streamErrorCount = 0;
    }

    if (mounted && obstacles.isNotEmpty) {
      setState(() => _obstacles = obstacles);

      final closest = obstacles.reduce((a, b) =>
          a.relativeSize > b.relativeSize ? a : b);

      double proximity = closest.relativeSize;
      bool isApproaching = false;

      if (_depthModelLoaded && _depthService.isInitialized) {
        final normalizedX = (closest.boundingBox.center.dx / image.width).clamp(0.0, 1.0);
        final normalizedY = (closest.boundingBox.center.dy / image.height).clamp(0.0, 1.0);

        final depthChangeResult = await _depthService.estimateDepthWithTrend(
          image, normalizedX, normalizedY, closest.label,
        );

        if (depthChangeResult != null) {
          proximity = depthChangeResult.current.normalizedDepth;
          isApproaching = depthChangeResult.isApproaching;
          debugPrint('🧠 Depth: ${closest.label} - ${depthChangeResult.fullDescription}');
        }
      }

      await _vibrationService.vibrateForProximity(
        proximity,
        intensityBoost: isApproaching ? 0.2 : 0.0,
      );
    }

    _processEnhancedContext(obstacles, textFuture, labelsFuture);
  }

  Future<void> _processEnhancedContext(
    List<DetectedObstacle> obstacles,
    Future<List<RecognizedTextBlock>> textFuture,
    Future<List<DetectedLabel>> labelsFuture,
  ) async {
    try {
      final textBlocks = await textFuture.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => <RecognizedTextBlock>[],
      );

      final labels = await labelsFuture.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => <DetectedLabel>[],
      );

      if (textBlocks.isNotEmpty) {
        debugPrint('📖 Text detected: ${textBlocks.map((t) => t.text).join(", ")}');
      }
      if (labels.isNotEmpty) {
        debugPrint('🏷️ Labels: ${labels.map((l) => l.label).join(", ")}');
      }

      if (mounted && (labels.isNotEmpty || textBlocks.isNotEmpty)) {
        setState(() {
          _detectedLabels = labels;
          _recognizedTexts = textBlocks;
        });
      }

      if (!_contextAggregator.shouldUpdate()) return;

      final obstacleInfos = obstacles.map((o) => ObstacleInfo(
        label: o.label,
        position: o.position,
        relativeSize: o.relativeSize,
      )).toList();

      final context = _contextAggregator.aggregate(
        obstacles: obstacleInfos,
        textBlocks: textBlocks,
        labels: labels,
      );

      // Don't queue new announcements while TTS is still speaking
      if (_ttsService.isSpeaking) return;

      // Speak aggregated context based on priority
      if (context.priority == ContextPriority.high &&
          _contextAggregator.isSignificantChange(context.summary)) {
        // High priority: very close obstacle — speak urgently if new
        await _ttsService.speakUrgent(context.summary);
      } else if (context.priority == ContextPriority.medium &&
          _contextAggregator.isSignificantChange(context.summary)) {
        // Medium priority: speak only when context changed (new text, etc.)
        await _ttsService.speak(context.summary);
      }
      // Low priority: silent — user can query manually

      _contextAggregator.markUpdated(context.summary);
      debugPrint('🧩 Context [${context.priority.name}]: ${context.summary}');
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final obstacles = await _mlKitService.processImageFile(imageFile.path);

      try { await File(imageFile.path).delete(); } catch (_) {}

      if (mounted) {
        setState(() => _obstacles = obstacles);
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

  // ─── ACTIONS ────────────────────────────────────────────

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
      if (!_isDetecting) _obstacles = [];
    });
    _ttsService.speak(_isDetecting ? 'Detection resumed' : 'Detection paused');
    if (!_isDetecting) _vibrationService.cancel();
  }

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
      await _ttsService.speak('Gemini AI not initialized.');
      return;
    }

    await _ttsService.speak('Analyzing scene...');

    try {
      final wasDetecting = _isDetecting;
      if (wasDetecting && _useStreamMode) {
        await _cameraController!.stopImageStream();
      }

      final XFile imageFile = await _cameraController!.takePicture();
      final description = await _geminiService.describeScene(imageFile.path);
      await _ttsService.speak(description);

      try { await File(imageFile.path).delete(); } catch (_) {}

      if (wasDetecting && _useStreamMode) {
        await _cameraController!.startImageStream(_processStreamImage);
      }
    } catch (e) {
      debugPrint('❌ Describe scene error: $e');
      await _ttsService.speak('Error analyzing scene');
    }
  }

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

  Future<void> _stopListeningAndAsk() async {
    await _speech.stop();
    setState(() => _isListening = false);

    if (_spokenText.isEmpty) {
      await _ttsService.speak('I did not hear anything. Try again.');
      return;
    }

    await _ttsService.speak('You asked: $_spokenText. Analyzing...');

    try {
      final wasDetecting = _isDetecting;
      if (wasDetecting && _useStreamMode) {
        await _cameraController!.stopImageStream();
      }

      final XFile imageFile = await _cameraController!.takePicture();
      final answer = await _geminiService.askQuestion(imageFile.path, _spokenText);
      await _ttsService.speak(answer);

      try { await File(imageFile.path).delete(); } catch (_) {}

      if (wasDetecting && _useStreamMode) {
        await _cameraController!.startImageStream(_processStreamImage);
      }
    } catch (e) {
      debugPrint('❌ Ask Gemini error: $e');
      await _ttsService.speak('Error processing your question');
    }
  }

  // ─── Proximity helpers ───────────────────────────────────

  String get _proximityStatusText {
    if (_obstacles.isEmpty) return 'Clear path ahead';
    final closest = _obstacles.reduce((a, b) =>
        a.relativeSize > b.relativeSize ? a : b);
    if (closest.isVeryClose) return 'Warning: ${closest.label} very close';
    if (closest.isClose) return 'Caution: ${closest.label} nearby';
    return '${closest.label} ahead';
  }

  int get _proximityLevel {
    if (_obstacles.isEmpty) return 0;
    final closest = _obstacles.reduce((a, b) =>
        a.relativeSize > b.relativeSize ? a : b);
    if (closest.isVeryClose) return 3;
    if (closest.isClose) return 2;
    return 1;
  }

  Color get _proximityColor {
    switch (_proximityLevel) {
      case 3: return const Color(0xFFE53935);
      case 2: return const Color(0xFFFFA726);
      case 1: return const Color(0xFF66BB6A);
      default: return const Color(0xFF43A047);
    }
  }

  IconData get _proximityIcon {
    switch (_proximityLevel) {
      case 3: return Icons.warning_rounded;
      case 2: return Icons.error_outline;
      case 1: return Icons.info_outline;
      default: return Icons.check_circle_outline;
    }
  }

  // ─── BUILD ─────────────────────────────────────────────

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
    return Semantics(
      label: 'Camera permission is required to detect obstacles',
      child: Center(
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
                'This app needs camera access to detect obstacles and keep you safe.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Semantics(
                button: true,
                label: 'Open device settings to grant camera permission',
                child: ElevatedButton(
                  onPressed: () => openAppSettings(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    minimumSize: const Size(double.infinity, 72),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Open Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        _buildProximityBar(),
        Expanded(
          child: _isInitialized && _cameraController != null
              ? _buildGestureCameraZone()
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(_statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                    ],
                  ),
                ),
        ),
        // Back button
        _buildBottomBar(),
      ],
    );
  }

  // ─── PROXIMITY BAR ──────────────────────────────────────

  Widget _buildProximityBar() {
    final status = _proximityStatusText;
    final color = _proximityColor;
    final icon = _proximityIcon;

    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Path status: $status',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border(bottom: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: _proximityLevel >= 2
                    ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 2)]
                    : [],
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    status,
                    style: TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: _proximityLevel >= 2 ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  if (_obstacles.isNotEmpty)
                    Text(
                      '${_obstacles.length} object${_obstacles.length > 1 ? 's' : ''} detected',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (_isDetecting ? Colors.green : Colors.orange).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isDetecting ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isDetecting ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: _isDetecting ? Colors.green : Colors.orange,
                      fontSize: 12, fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── GESTURE CAMERA ZONE ────────────────────────────────

  Widget _buildGestureCameraZone() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () {
        _ttsService.speak('Describing scene...');
        _describeScene();
      },
      onLongPress: () {
        if (_isListening) {
          _stopListeningAndAsk();
        } else {
          _ttsService.speak('Listening...');
          _startListening();
        }
      },
      onLongPressUp: () {
        if (_isListening) _stopListeningAndAsk();
      },
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          _toggleDetection();
        }
      },
      child: Semantics(
        label: 'Camera view. Double tap to describe scene. Long press to ask a question. Swipe down to pause or resume.',
        child: Stack(
          children: [
            CameraPreviewWidget(
              controller: _cameraController!,
              obstacles: _obstacles,
            ),
            if (_isListening)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mic, color: Colors.red, size: 64),
                        SizedBox(height: 12),
                        Text('Listening...', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('Release to send question', style: TextStyle(color: Colors.white70, fontSize: 16)),
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

  // ─── BOTTOM BAR ─────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: 'Go back to obstacle detector menu',
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_back, color: Colors.white, size: 24),
                      SizedBox(width: 10),
                      Text('BACK', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Double-tap: Describe  •  Hold: Voice  •  Swipe ↓: Pause',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
