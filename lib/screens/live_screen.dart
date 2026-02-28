import 'dart:async';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/accessible_live_connector.dart';
import '../utils/audio_input.dart';
import '../utils/audio_output.dart';

/// Production Live Screen — Accessible AI assistant via Gemini Live API.
///
/// Full-featured, polished version without debug panels.
/// Features: hardware AEC, barge-in, earcons, PTT mode, VAD tuning.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  // ── Core ──
  LiveSession? _session;
  CameraController? _cameraController;
  final AudioInput _audioInput = AudioInput();
  final AudioOutput _audioOutput = AudioOutput();
  static const _imageChannel = MethodChannel('image_converter_channel');

  // ── State ──
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isStreamingAudio = false;
  bool _isStreamingVideo = false;
  late final Future<void> _cameraReady;

  CameraImage? _latestFrame;
  Timer? _videoSendTimer;
  bool _isConvertingFrame = false;

  // ── Accessibility ──
  bool _aiIsSpeaking = false;
  bool _pushToTalkMode = true; // true = Hold to Talk, false = Real Time
  bool _pttPressed = false;
  bool _isFirstAudioChunk = true;
  String _statusMessage = 'Initializing...';

  // ── Monitoring ──
  Timer? _monitorTimer;
  bool _isMonitoring = false;

  // ═══════════════════════════════════════════════════
  // EARCONS (haptic + audio cues for blind users)
  // ═══════════════════════════════════════════════════

  void _playListeningEarcon() {
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  void _playProcessingEarcon() {
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.mediumImpact();
    });
  }

  void _playResponseEarcon() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
  }

  // ═══════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraReady = _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAll();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _stopAll();
    } else if (state == AppLifecycleState.resumed && !_isConnected) {
      _cameraReady = _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setStatus('No camera found');
        return;
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        cam,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {});
        _setStatus('Ready — tap START to connect');
      }
    } catch (e) {
      _setStatus('Camera error');
      debugPrint('❌ Camera init: $e');
    }
  }

  void _setStatus(String msg) {
    if (mounted) setState(() => _statusMessage = msg);
  }

  // ═══════════════════════════════════════════════════
  // CONNECT (AccessibleLiveConnector with VAD config)
  // ═══════════════════════════════════════════════════

  Future<void> _connect() async {
    if (_isConnected || _isConnecting) return;
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to Gemini Live...';
    });

    try {
      final connector = AccessibleLiveConnector(
        model: 'gemini-live-2.5-flash-native-audio',
        location: 'us-central1',
        systemInstruction: Content.text('''
You are a vision assistant for blind users. You are their eyes.

Response rules:
1. Use directions: ahead, left, right, above, below
2. Estimate distances: very close (<1m), close (3m), medium (5m), far (10m+)
3. Prioritize hazards: stairs, steps, vehicles, obstacles, holes
4. Keep each response under 20 words, be concise
5. Speak clearly and at moderate pace
6. Focus on what matters for safe navigation
'''),
        liveGenerationConfig: LiveGenerationConfig(
          responseModalities: [ResponseModalities.audio],
          speechConfig: SpeechConfig(voiceName: 'Aoede'),
        ),
        startOfSpeechSensitivity: 'START_SENSITIVITY_LOW',
        endOfSpeechSensitivity: 'END_SENSITIVITY_LOW',
        silenceDurationMs: 1500,
      );

      final session = await connector.connect();
      _session = session;
      _isConnected = true;
      _isConnecting = false;
      _setStatus('Live — speaking to Gemini');

      _playListeningEarcon();
      _receiveLoop();
    } catch (e) {
      debugPrint('❌ Connect error: $e');
      _isConnecting = false;
      _setStatus('Connection error — tap to retry');
    }
  }

  // ═══════════════════════════════════════════════════
  // RECEIVE LOOP (barge-in + earcons)
  // ═══════════════════════════════════════════════════

  Future<void> _receiveLoop() async {
    while (_isConnected && _session != null) {
      try {
        await for (final response in _session!.receive()) {
          if (!_isConnected) break;

          final msg = response.message;

          if (msg is LiveServerContent) {
            // Barge-in: AI interrupted by user
            if (msg.interrupted == true) {
              await _audioOutput.stopImmediately();
              _aiIsSpeaking = false;
              _isFirstAudioChunk = true;
              if (mounted) setState(() {});
              continue;
            }

            final parts = msg.modelTurn?.parts;
            if (parts != null) {
              for (final part in parts) {
                if (part is InlineDataPart && part.mimeType.contains('audio')) {
                  if (_isFirstAudioChunk) {
                    _isFirstAudioChunk = false;
                    _playResponseEarcon();
                    _aiIsSpeaking = true;
                    _audioOutput.init();
                    if (mounted)
                      setState(() => _statusMessage = 'AI speaking...');
                  }
                  _audioOutput.addAudioStream(part.bytes);
                }
              }
            }

            if (msg.turnComplete == true) {
              _aiIsSpeaking = false;
              _isFirstAudioChunk = true;
              _playListeningEarcon();
              if (mounted) setState(() => _statusMessage = 'Live — listening');
            }
          } else if (msg.runtimeType.toString() == 'LiveServerSetupComplete') {
            _playListeningEarcon();
          }
        }
        if (_isConnected) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (e) {
        if (!_isConnected) break;
        if (e.toString().contains('Closed')) {
          _stopAll();
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  // ═══════════════════════════════════════════════════
  // START / STOP
  // ═══════════════════════════════════════════════════

  Future<void> _startAll() async {
    if (!_isConnected) await _connect();
    if (!_isConnected) return;

    await _cameraReady;
    _startAudioStream();
    _startVideoStream();
  }

  Future<void> _startAudioStream() async {
    if (_isStreamingAudio) return;
    _isStreamingAudio = true;
    _audioOutput.init();

    try {
      final audioStream = await _audioInput.startRecordingStream();
      if (audioStream == null) {
        _isStreamingAudio = false;
        return;
      }
      audioStream.listen((data) async {
        if (!_isConnected || _session == null) return;

        // Hardware AEC handles echo — mic stays active for barge-in
        // PTT: only send when button is held
        if (_pushToTalkMode && !_pttPressed) return;

        try {
          await _session!.sendAudioRealtime(
            InlineDataPart('audio/pcm;rate=16000', data),
          );
        } catch (e) {
          if (e.toString().contains('Closed')) {
            _isStreamingAudio = false;
          }
        }
      }, onError: (e) => debugPrint('❌ Mic: $e'));
    } catch (e) {
      debugPrint('❌ Mic start: $e');
      _isStreamingAudio = false;
    }
  }

  void _startVideoStream() {
    if (_isStreamingVideo) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _isStreamingVideo = true;

    _cameraController!.startImageStream((CameraImage image) {
      _latestFrame = image;
    });

    _videoSendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _convertAndSendFrame();
    });
  }

  Future<void> _convertAndSendFrame() async {
    final session = _session;
    final frame = _latestFrame;
    if (!_isConnected || !_isStreamingVideo || session == null) return;
    if (frame == null || _isConvertingFrame) return;

    _isConvertingFrame = true;
    try {
      final jpegBytes = await _imageChannel.invokeMethod('convertYuvToJpeg', {
        'width': frame.width,
        'height': frame.height,
        'yPlane': frame.planes[0].bytes,
        'uPlane': frame.planes.length > 1 ? frame.planes[1].bytes : null,
        'vPlane': frame.planes.length > 2 ? frame.planes[2].bytes : null,
        'yRowStride': frame.planes[0].bytesPerRow,
        'uvPixelStride':
            frame.planes.length > 1 ? frame.planes[1].bytesPerPixel ?? 1 : 1,
        'quality': 40,
      });

      if (!_isConnected || _session == null) return;

      await session.sendVideoRealtime(InlineDataPart('image/jpeg', jpegBytes));
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Closed')) {
        _isStreamingVideo = false;
        return;
      }
    } finally {
      _isConvertingFrame = false;
    }
  }

  Future<void> _sendTextPrompt(String text) async {
    if (!_isConnected || _session == null) return;
    try {
      await _session!.send(input: Content.text(text), turnComplete: true);
    } catch (e) {
      debugPrint('❌ Send: $e');
    }
  }

  // ── Traffic Light Monitoring ──
  void _toggleTrafficMonitoring() {
    if (_isMonitoring) {
      // Stop monitoring
      _monitorTimer?.cancel();
      _monitorTimer = null;
      setState(() => _isMonitoring = false);
      _sendTextPrompt('Stop monitoring the traffic light. Thank you.');
      // Show feedback dialog
      _showTrafficFeedbackDialog();
      return;
    }

    if (!_isConnected) return;

    // Start monitoring
    setState(() => _isMonitoring = true);
    HapticFeedback.mediumImpact();

    // Send initial prompt — tell current color once
    _sendTextPrompt(
      'You are an assistant for a visually impaired pedestrian. Look directly ahead for the pedestrian crossing signal (the red or green man) and tell me its current colour. Keep your answers extremely brief.'
      'After your first answer, stay completely silent unless the signal changes.'
      'When the signal changes to green, say exactly this: The pedestrian signal is now green. Crucially: Do not tell me it is safe to cross. Simply report the signal status so I can use my own judgement and hearing to decide when to step into the road.',
    );

    // Re-prompt every 5 seconds — Gemini only speaks on change
    _monitorTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isConnected || !_isMonitoring) {
        _monitorTimer?.cancel();
        _monitorTimer = null;
        if (mounted) setState(() => _isMonitoring = false);
        return;
      }
      _sendTextPrompt(
        'Check the traffic light again. '
        'Only tell me if the color has CHANGED since last time. '
        'If it is still the same color, say absolutely nothing. '
        'If it changed, tell me the new color and whether it is safe to cross.',
      );
    });
  }

  // ── Traffic Feedback Dialog ──
  void _showTrafficFeedbackDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF000000),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Traffic Light Monitoring',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: const Text(
              'Was this successful?',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _uploadTrafficFeedback(false);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFFFFFF).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'No',
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _uploadTrafficFeedback(true);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Yes',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _uploadTrafficFeedback(bool wasSuccessful) async {
    try {
      await FirebaseFirestore.instance.collection('traffic_feedback').add({
        'wasSuccessful': wasSuccessful,
        'timestamp': FieldValue.serverTimestamp(),
        'deviceTime': DateTime.now().toIso8601String(),
      });
      debugPrint('✅ Traffic feedback uploaded: $wasSuccessful');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasSuccessful
                  ? 'Thanks! Feedback recorded.'
                  : 'Thanks for the feedback.',
            ),
            backgroundColor:
                wasSuccessful
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFFFFFFFF),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Traffic feedback upload failed: $e');
    }
  }

  /// Send ~2s of silence audio so VAD detects end of speech.
  /// Without this, releasing PTT stops sending data entirely,
  /// and the server never sees the speech→silence transition.
  Future<void> _sendSilenceTail() async {
    if (!_isConnected || _session == null) return;
    // PCM 16-bit mono at 16kHz = 32000 bytes/sec
    // Send 100ms chunks × 20 = 2 seconds of silence
    final silence = Uint8List(3200); // 100ms of zeros
    for (int i = 0; i < 20; i++) {
      if (!_isConnected || _session == null) break;
      try {
        await _session!.sendAudioRealtime(
          InlineDataPart('audio/pcm;rate=16000', silence),
        );
      } catch (_) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _stopAll() {
    _isStreamingAudio = false;
    _isStreamingVideo = false;
    _videoSendTimer?.cancel();
    _videoSendTimer = null;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _isMonitoring = false;
    _latestFrame = null;
    _isConvertingFrame = false;
    _aiIsSpeaking = false;

    try {
      _cameraController?.stopImageStream();
    } catch (_) {}

    _audioInput.stopRecording();
    _audioOutput.stop();

    _isConnected = false;
    _isConnecting = false;
    _session?.close();
    _session = null;
    if (mounted) setState(() => _statusMessage = 'Disconnected');
  }

  // ═══════════════════════════════════════════════════
  // BUILD UI — Accessible, user-friendly design
  // ═══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    _buildCompactCamera(),
                    const SizedBox(height: 24),
                    _buildAIStatusRing(),
                    const SizedBox(height: 28),
                    if (_isConnected) ...[
                      _buildQuickActions(),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  // ── Status Bar ──
  Widget _buildStatusBar() {
    final bool connected = _isConnected;
    final Color accent =
        connected
            ? (_aiIsSpeaking
                ? const Color(0xFFFFFFFF)
                : const Color(0xFFFFFFFF))
            : (_isConnecting
                ? const Color(0xFFFFFFFF)
                : const Color(0xFF555555));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.3), width: 1),
        ),
      ),
      child: Semantics(
        liveRegion: true,
        label: 'Status: $_statusMessage',
        child: Row(
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow:
                    connected
                        ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ]
                        : [],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (connected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFFFFFF).withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fiber_manual_record,
                      color: Color(0xFFFFFFFF),
                      size: 8,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
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

  // ── Compact Camera Preview ──
  Widget _buildCompactCamera() {
    final bool ready =
        _cameraController != null && _cameraController!.value.isInitialized;

    return Semantics(
      label: ready ? 'Camera is active' : 'Camera loading',
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                _isConnected
                    ? const Color(0xFFFFFFFF).withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child:
            ready
                ? Stack(
                  children: [
                    Center(child: CameraPreview(_cameraController!)),
                    // Overlay gradient
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              const Color(0xFF000000).withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Camera label
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.videocam,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Camera Active',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                )
                : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.videocam_off,
                        color: Colors.white.withValues(alpha: 0.3),
                        size: 28,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Camera loading...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }

  // ── AI Status Ring Visualization ──
  Widget _buildAIStatusRing() {
    // Determine ring color based on mode and state
    final Color ringColor;
    final String stateLabel;
    final IconData stateIcon;
    final bool isActive;

    if (!_isConnected) {
      ringColor = const Color(0xFF333333);
      stateLabel = 'Not connected';
      stateIcon = Icons.power_off;
      isActive = false;
    } else if (_aiIsSpeaking) {
      ringColor = const Color(0xFFFFFFFF);
      stateLabel = 'AI is speaking';
      stateIcon = Icons.volume_up_rounded;
      isActive = true;
    } else if (_pushToTalkMode) {
      // PTT mode
      ringColor =
          _pttPressed ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF);
      stateLabel = _pttPressed ? 'Listening to you' : 'Ready — hold to talk';
      stateIcon = _pttPressed ? Icons.mic : Icons.mic_none;
      isActive = _pttPressed;
    } else {
      // Real Time mode — always listening
      ringColor = const Color(0xFFFFFFFF);
      stateLabel = 'Listening in real time';
      stateIcon = Icons.hearing;
      isActive = true;
    }

    return Semantics(
      liveRegion: true,
      label: stateLabel,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: isActive ? 5 : 3),
              boxShadow:
                  isActive
                      ? [
                        BoxShadow(
                          color: ringColor.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                        BoxShadow(
                          color: ringColor.withValues(alpha: 0.15),
                          blurRadius: 60,
                          spreadRadius: 15,
                        ),
                      ]
                      : [],
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ringColor.withValues(alpha: isActive ? 0.12 : 0.05),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    stateIcon,
                    key: ValueKey(stateIcon),
                    color: ringColor,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              color: ringColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
            child: Text(stateLabel),
          ),
        ],
      ),
    );
  }

  // ── Quick Action Buttons ──
  Widget _buildQuickActions() {
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 8,
      runSpacing: 8,
      children: [
        _actionButton(
          icon: Icons.visibility,
          label: 'See',
          prompt: 'What do you see?',
          color: const Color(0xFFFFFFFF),
        ),
        _actionButton(
          icon: Icons.auto_stories,
          label: 'Read',
          prompt: 'Read any text',
          color: const Color(0xFFFFFFFF),
        ),
        _actionButton(
          icon: Icons.traffic,
          label: _isMonitoring ? 'Stop' : 'Traffic',
          prompt: '',
          color:
              _isMonitoring ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF),
          onTapOverride: () => _toggleTrafficMonitoring(),
        ),
        _actionButton(
          icon: Icons.landscape,
          label: 'Scene',
          prompt: 'Describe the scene around me in detail',
          color: const Color(0xFFFFFFFF),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required String prompt,
    required Color color,
    VoidCallback? onTapOverride,
  }) {
    return Semantics(
      button: true,
      label: '$label. Tap to ask: $prompt',
      child: GestureDetector(
        onTap: onTapOverride ?? () => _sendTextPrompt(prompt),
        child: Container(
          width: 90,
          height: 80,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Mode Toggle ──
  Widget _buildModeToggle() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // Hold to Talk option
          Expanded(
            child: Semantics(
              label: 'Mode: Hold to Talk',
              button: true,
              child: GestureDetector(
                onTap: () => setState(() => _pushToTalkMode = true),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient:
                        _pushToTalkMode
                            ? const LinearGradient(
                              colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
                            )
                            : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app,
                          color:
                              _pushToTalkMode ? Colors.black : Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Hold to Talk',
                          style: TextStyle(
                            color:
                                _pushToTalkMode ? Colors.black : Colors.white38,
                            fontSize: 14,
                            fontWeight:
                                _pushToTalkMode
                                    ? FontWeight.w900
                                    : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Real Time option
          Expanded(
            child: Semantics(
              label: 'Mode: Real Time',
              button: true,
              child: GestureDetector(
                onTap:
                    () => setState(() {
                      _pushToTalkMode = false;
                      _pttPressed = false; // Reset PTT state
                    }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient:
                        !_pushToTalkMode
                            ? const LinearGradient(
                              colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
                            )
                            : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.hearing,
                          color:
                              !_pushToTalkMode ? Colors.black : Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Real Time',
                          style: TextStyle(
                            color:
                                !_pushToTalkMode
                                    ? Colors.black
                                    : Colors.white38,
                            fontSize: 14,
                            fontWeight:
                                !_pushToTalkMode
                                    ? FontWeight.w900
                                    : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Panel (PTT + Controls) ──
  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF000000),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Connected state ──
          if (_isConnected) ...[
            // ── Mode toggle ──
            _buildModeToggle(),
            const SizedBox(height: 12),
            // ── PTT button (only in Hold to Talk mode) ──
            if (_pushToTalkMode) ...[
              Semantics(
                button: true,
                label:
                    _pttPressed
                        ? 'Speaking. Release to send.'
                        : 'Hold to talk.',
                child: Listener(
                  onPointerDown: (_) {
                    setState(() => _pttPressed = true);
                    _playListeningEarcon();
                  },
                  onPointerUp: (_) {
                    setState(() => _pttPressed = false);
                    _playProcessingEarcon();
                    _sendSilenceTail();
                  },
                  onPointerCancel: (_) {
                    setState(() => _pttPressed = false);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: double.infinity,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient:
                          _pttPressed
                              ? const LinearGradient(
                                colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                              : const LinearGradient(
                                colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: (_pttPressed
                                  ? const Color(0xFFFFFFFF)
                                  : const Color(0xFFFFFFFF))
                              .withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _pttPressed ? Icons.mic : Icons.mic_none,
                            color: Colors.black,
                            size: 40,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            _pttPressed ? 'SPEAKING...' : 'HOLD TO TALK',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // ── Bottom row: Back + End Live ──
            Row(
              children: [
                // Back button
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Go back',
                    child: GestureDetector(
                      onTap: () {
                        _stopAll();
                        if (mounted) Navigator.pop(context);
                      },
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white70,
                                size: 22,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'BACK',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // End Live button
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'End live session',
                    child: GestureDetector(
                      onTap: _stopAll,
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFFFFFF,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFFFFFFFF,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.stop_rounded,
                                color: Color(0xFFFFFFFF),
                                size: 22,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'END LIVE',
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // ── Not connected: START LIVE button ──
            Semantics(
              button: true,
              label: 'Start live conversation with voice and camera',
              child: GestureDetector(
                onTap: _isConnecting ? null : () => _startAll(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient:
                        _isConnecting
                            ? LinearGradient(
                              colors: [
                                const Color(0xFFFFFFFF).withValues(alpha: 0.8),
                                const Color(0xFFFFFFFF),
                              ],
                            )
                            : const LinearGradient(
                              colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFFFFF).withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child:
                        _isConnecting
                            ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                ),
                                SizedBox(width: 16),
                                Text(
                                  'CONNECTING...',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            )
                            : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 40,
                                ),
                                SizedBox(width: 14),
                                Text(
                                  'START LIVE',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Back button (disconnected)
            Semantics(
              button: true,
              label: 'Go back',
              child: GestureDetector(
                onTap: () {
                  if (mounted) Navigator.pop(context);
                },
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'BACK',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
