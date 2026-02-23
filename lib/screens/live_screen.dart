import 'dart:async';

import 'package:camera/camera.dart';
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
  bool _pushToTalkMode = false;
  bool _pttPressed = false;
  bool _isFirstAudioChunk = true;
  String _statusMessage = 'Initializing...';

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
                    if (mounted) setState(() => _statusMessage = 'AI speaking...');
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
      audioStream.listen(
        (data) async {
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
        },
        onError: (e) => debugPrint('❌ Mic: $e'),
      );
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
      final jpegBytes = await _imageChannel.invokeMethod(
        'convertYuvToJpeg',
        {
          'width': frame.width,
          'height': frame.height,
          'yPlane': frame.planes[0].bytes,
          'uPlane': frame.planes.length > 1 ? frame.planes[1].bytes : null,
          'vPlane': frame.planes.length > 2 ? frame.planes[2].bytes : null,
          'yRowStride': frame.planes[0].bytesPerRow,
          'uvPixelStride':
              frame.planes.length > 1 ? frame.planes[1].bytesPerPixel ?? 1 : 1,
          'quality': 40,
        },
      );

      if (!_isConnected || _session == null) return;

      await session.sendVideoRealtime(
        InlineDataPart('image/jpeg', jpegBytes),
      );
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
      await _session!.send(
        input: Content.text(text),
        turnComplete: true,
      );
    } catch (e) {
      debugPrint('❌ Send: $e');
    }
  }

  Future<void> _sendTurnComplete() async {
    if (!_isConnected || _session == null) return;
    try {
      await _session!.send(
        input: Content.text(''),
        turnComplete: true,
      );
    } catch (e) {
      debugPrint('❌ turnComplete: $e');
    }
  }

  void _stopAll() {
    _isStreamingAudio = false;
    _isStreamingVideo = false;
    _videoSendTimer?.cancel();
    _videoSendTimer = null;
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
  // BUILD UI — Clean production interface
  // ═══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(),
            Expanded(child: _buildCameraPreview()),
            if (_isConnected) _buildQuickPrompts(),
            _buildControlPanel(),
          ],
        ),
      ),
    );
  }

  // ── Status bar ──
  Widget _buildStatusBar() {
    final Color statusColor = _isConnected
        ? (_aiIsSpeaking ? Colors.orange : Colors.green)
        : (_isConnecting ? Colors.orange : Colors.grey);

    return Semantics(
      liveRegion: true,
      label: 'Live status: $_statusMessage',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          border: Border(bottom: BorderSide(color: statusColor, width: 3)),
        ),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: _isConnected
                    ? [BoxShadow(color: statusColor.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 2)]
                    : [],
              ),
              child: Icon(
                _isConnected
                    ? (_aiIsSpeaking ? Icons.volume_up : Icons.mic)
                    : (_isConnecting ? Icons.sync : Icons.mic_off),
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
            // PTT toggle
            if (_isConnected)
              IconButton(
                icon: Icon(
                  _pushToTalkMode ? Icons.touch_app : Icons.mic,
                  color: _pushToTalkMode ? Colors.orange : Colors.white70,
                ),
                tooltip: _pushToTalkMode ? 'Push-to-Talk ON' : 'Always Listen',
                onPressed: () => setState(() => _pushToTalkMode = !_pushToTalkMode),
              ),
            // LIVE badge
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

  // ── Camera preview ──
  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(_statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 18)),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Center(child: CameraPreview(_cameraController!)),
        // Mode indicator overlay (minimal)
        if (_isConnected)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _pushToTalkMode ? '🎤 Push-to-Talk' : '👂 Always Listening',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  // ── Quick prompts ──
  Widget _buildQuickPrompts() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _promptChip('What do you see?'),
          _promptChip('Any obstacles?'),
          _promptChip('Read any text'),
          _promptChip('Describe the scene'),
        ],
      ),
    );
  }

  Widget _promptChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: () => _sendTextPrompt(text),
      backgroundColor: Colors.blue.shade800,
      labelStyle: const TextStyle(color: Colors.white),
    );
  }

  // ── Control panel (START/STOP + PTT hold button + Back) ──
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
          // PTT hold button (visible when PTT mode is on and connected)
          if (_pushToTalkMode && _isConnected) ...[
            Semantics(
              button: true,
              label: 'Hold to talk. Release to send.',
              child: GestureDetector(
                onLongPressStart: (_) {
                  setState(() => _pttPressed = true);
                  _playListeningEarcon();
                },
                onLongPressEnd: (_) {
                  setState(() => _pttPressed = false);
                  _sendTurnComplete();
                  _playProcessingEarcon();
                },
                onLongPressCancel: () => setState(() => _pttPressed = false),
                onTapDown: (_) {
                  setState(() => _pttPressed = true);
                  _playListeningEarcon();
                },
                onTapUp: (_) {
                  setState(() => _pttPressed = false);
                  _sendTurnComplete();
                  _playProcessingEarcon();
                },
                onTapCancel: () => setState(() => _pttPressed = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: double.infinity,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: _pttPressed
                        ? const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFFF5252)])
                        : const LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF42A5F5)]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (_pttPressed ? Colors.red : Colors.blue).withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _pttPressed ? Icons.mic : Icons.mic_off,
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          _pttPressed ? 'SPEAKING...' : 'HOLD TO TALK',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
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

          // START / END LIVE button
          Semantics(
            button: true,
            label: _isConnected
                ? 'End live conversation'
                : 'Start live conversation with voice and camera',
            child: GestureDetector(
              onTap: () async {
                if (_isConnected) {
                  _stopAll();
                } else {
                  await _startAll();
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
                              width: 24,
                              height: 24,
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
                              color: Colors.white,
                              size: 32,
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
            label: 'Go back to main menu',
            child: GestureDetector(
              onTap: () async {
                if (_isConnected) _stopAll();
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
