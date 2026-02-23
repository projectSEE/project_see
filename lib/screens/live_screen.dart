import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/tts_service.dart';
import '../services/gemini_live_service.dart';
import '../services/audio_stream_service.dart';
import '../services/audio_player_service.dart';
import '../services/unified_media_stream_service.dart';
import '../widgets/camera_preview.dart';

/// Live Screen — Real-time AI assistant via Gemini Live API
/// Provides continuous audio/video conversation with Gemini.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  // Camera
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  CameraDescription? _selectedCamera;

  // Services
  final TTSService _ttsService = TTSService();
  final GeminiLiveService _geminiLiveService = GeminiLiveService();
  final AudioStreamService _audioStreamService = AudioStreamService();
  final AudioPlayerService _audioPlayerService = AudioPlayerService();
  final UnifiedMediaStreamService _unifiedMediaService = UnifiedMediaStreamService();

  // State
  bool _isInitialized = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _hasPermission = false;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disconnect();
    _cameraController?.dispose();
    _ttsService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _disconnect();
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  // ─── INITIALIZATION ─────────────────────────────────────

  Future<void> _initializeApp() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (cameraStatus.isGranted && micStatus.isGranted) {
      setState(() {
        _hasPermission = true;
        _statusMessage = 'Initializing camera...';
      });

      await _ttsService.initialize();
      await _initializeCamera();

      await _ttsService.speak(
        'Live assistant ready. Tap the button below to start a conversation with Gemini.',
      );
    } else {
      setState(() => _statusMessage = 'Camera and microphone permissions required');
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

      // Start image stream to feed frames to Gemini when connected
      await _cameraController!.startImageStream(_processFrame);

      setState(() {
        _isInitialized = true;
        _statusMessage = 'Ready — tap START to connect';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Camera error: $e');
    }
  }

  void _processFrame(CameraImage image) {
    // If connected, feed frames to unified media service
    if (_isConnected && _unifiedMediaService.isActive) {
      _unifiedMediaService.processCameraFrame(image).catchError((e) {
        debugPrint('❌ processCameraFrame error: $e');
      });
    }
  }

  // ─── LIVE MODE CONTROLS ─────────────────────────────────

  Future<void> _connect() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to Gemini Live...';
    });

    await _ttsService.speak('Connecting to Gemini Live...');

    try {
      await _geminiLiveService.initialize();
      await _audioPlayerService.initialize();

      // Gemini returns audio directly
      _geminiLiveService.onAudioResponse = (audioData) {
        _audioPlayerService.queueAudio(audioData);
      };

      // Fallback: text response via TTS
      _geminiLiveService.onResponse = (text) {
        debugPrint('📝 Text fallback: $text');
        _ttsService.speak(text);
      };

      _geminiLiveService.onError = (error) {
        _ttsService.speak('Error: $error');
      };

      // When ready, start streaming
      _geminiLiveService.onReady = () async {
        debugPrint('🚀 Gemini ready — starting unified A/V streaming');

        await Future.delayed(const Duration(milliseconds: 300));
        await _sendInitialFrame();
        _geminiLiveService.sendText('Describe what you see briefly. What is in front of me?');

        await Future.delayed(const Duration(seconds: 1));

        _unifiedMediaService.start();

        if (_unifiedMediaService.mediaStream != null) {
          _geminiLiveService.sendMediaStream(_unifiedMediaService.mediaStream!);
          debugPrint('📹 Unified A/V stream connected');
        }

        final audioStream = await _audioStreamService.startRecordingStream();
        if (audioStream != null) {
          audioStream.listen((audioData) {
            _unifiedMediaService.addAudio(audioData);
          });
          debugPrint('🎤 Audio feeding to unified stream');
        }

        debugPrint('✅ Live mode active!');
      };

      await _geminiLiveService.connect();

      if (_geminiLiveService.isConnected) {
        await _ttsService.speak('Connected! I can now see and hear you.');
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _statusMessage = 'Live — speaking to Gemini';
        });
      } else {
        setState(() {
          _isConnecting = false;
          _statusMessage = 'Failed to connect';
        });
        await _ttsService.speak('Failed to connect. Please try again.');
      }
    } catch (e) {
      debugPrint('❌ Connection error: $e');
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Connection error';
      });
      await _ttsService.speak('Error connecting to Gemini Live');
    }
  }

  Future<void> _disconnect() async {
    _unifiedMediaService.stop();
    await _audioStreamService.stopRecording();
    await _audioPlayerService.stop();
    await _geminiLiveService.disconnect();

    if (mounted) {
      setState(() {
        _isConnected = false;
        _statusMessage = 'Disconnected';
      });
    }
  }

  Future<void> _sendInitialFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      final wasStreaming = _cameraController!.value.isStreamingImages;
      if (wasStreaming) await _cameraController!.stopImageStream();

      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List imageBytes = await File(imageFile.path).readAsBytes();
      await _geminiLiveService.sendImage(imageBytes);

      try { await File(imageFile.path).delete(); } catch (_) {}

      if (wasStreaming) {
        await _cameraController!.startImageStream(_processFrame);
      }
    } catch (e) {
      debugPrint('❌ Send initial frame error: $e');
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
      label: 'Camera and microphone permissions are required for live mode',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, size: 80, color: Colors.white54),
              const SizedBox(height: 24),
              const Text(
                'Permissions Required',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Live mode needs camera and microphone access to communicate with Gemini AI.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Semantics(
                button: true,
                label: 'Open device settings to grant permissions',
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
        // Status bar
        _buildStatusBar(),

        // Camera preview
        Expanded(
          child: _isInitialized && _cameraController != null
              ? CameraPreviewWidget(
                  controller: _cameraController!,
                  obstacles: const [],
                )
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

        // Controls
        _buildControlPanel(),
      ],
    );
  }

  Widget _buildStatusBar() {
    final Color statusColor = _isConnected
        ? Colors.green
        : (_isConnecting ? Colors.orange : Colors.grey);
    final String statusText = _isConnected
        ? 'Live — speaking to Gemini'
        : (_isConnecting ? 'Connecting...' : 'Not connected');

    return Semantics(
      liveRegion: true,
      label: 'Live status: $statusText',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          border: Border(bottom: BorderSide(color: statusColor, width: 3)),
        ),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: _isConnected
                    ? [BoxShadow(color: statusColor.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 2)]
                    : [],
              ),
              child: Icon(
                _isConnected ? Icons.mic : (_isConnecting ? Icons.sync : Icons.mic_off),
                color: Colors.white, size: 16,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                statusText,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
            if (_isConnected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
                    SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Primary: START/END LIVE button
          Semantics(
            button: true,
            label: _isConnected
                ? 'End live conversation with Gemini'
                : 'Start live conversation with Gemini using voice and camera',
            child: GestureDetector(
              onTap: () async {
                if (_isConnected) {
                  await _disconnect();
                  await _ttsService.speak('Live mode stopped.');
                } else {
                  await _connect();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                height: 80,
                decoration: BoxDecoration(
                  gradient: _isConnected
                      ? const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFFF5252)])
                      : const LinearGradient(colors: [Color(0xFF1976D2), Color(0xFF42A5F5)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _isConnected
                          ? Colors.red.withValues(alpha: 0.4)
                          : Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: _isConnecting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                            ),
                            SizedBox(width: 14),
                            Text('CONNECTING...', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isConnected ? Icons.stop : Icons.videocam,
                              color: Colors.white, size: 32,
                            ),
                            const SizedBox(width: 14),
                            Text(
                              _isConnected ? 'END LIVE' : 'START LIVE',
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Back button
          Semantics(
            button: true,
            label: 'Go back to obstacle detector menu',
            child: GestureDetector(
              onTap: () async {
                if (_isConnected) await _disconnect();
                if (mounted) Navigator.pop(context);
              },
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
        ],
      ),
    );
  }
}
