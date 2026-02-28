import 'dart:async';

import 'package:camera/camera.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/accessible_live_connector.dart';
import '../utils/audio_input.dart';
import '../utils/audio_output.dart';

/// Blind-accessible multimodal live streaming screen.
///
/// Implements the full Vertex AI Multimodal Live API with accessibility:
/// - VAD: LOW start/end sensitivity (ignores cane taps, traffic, screen readers)
/// - Earcons: audio cues for "listening" and "processing" states
/// - Hard barge-in: instantly purges audio buffer on interruption
/// - Echo cancellation: mutes mic while AI speaks to prevent feedback
/// - Push-to-talk: optional fallback mode
class LiveTestScreen extends StatefulWidget {
  const LiveTestScreen({super.key});

  @override
  State<LiveTestScreen> createState() => _LiveTestScreenState();
}

class _LiveTestScreenState extends State<LiveTestScreen> {
  // ═══════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════

  LiveSession? _session;
  CameraController? _cameraController;
  final AudioInput _audioInput = AudioInput();
  final AudioOutput _audioOutput = AudioOutput();

  static const _imageChannel = MethodChannel('image_converter_channel');

  bool _isConnected = false;
  bool _isStreamingAudio = false;
  bool _isStreamingVideo = false;

  // Camera init future — so we can await in _startAll
  late final Future<void> _cameraReady;

  // Latest camera frame (continuously updated by image stream)
  CameraImage? _latestFrame;
  Timer? _videoSendTimer;
  bool _isConvertingFrame = false;

  // ── Accessibility state ──
  bool _aiIsSpeaking = false; // Track AI speaking state for earcons
  bool _pushToTalkMode = false; // PTT mode toggle
  bool _pttPressed = false; // PTT button state
  bool _isFirstAudioChunk = true; // Earcon: first audio = "processing"

  // Stats
  int _audioChunksSent = 0;
  int _videoFramesSent = 0;
  int _serverMessages = 0;
  int _audioChunksReceived = 0;
  int _connectTimeMs = 0;

  // Debug log
  final List<_LogEntry> _logEntries = [];
  final ScrollController _logScroll = ScrollController();

  // ═══════════════════════════════════════════════════
  // LOG
  // ═══════════════════════════════════════════════════

  void _log(String msg, [String level = 'info']) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    debugPrint('[$ts] $msg');
    if (!mounted) return;
    setState(() {
      _logEntries.add(_LogEntry(ts, msg, level));
      if (_logEntries.length > 200) _logEntries.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  // ═══════════════════════════════════════════════════
  // EARCONS (audio cues for blind users)
  // ═══════════════════════════════════════════════════

  /// Play a short "pop" sound — user started speaking / listening active
  void _playListeningEarcon() {
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
    _log('🔔 Earcon: listening');
  }

  /// Play "processing" chime — AI is thinking
  void _playProcessingEarcon() {
    HapticFeedback.mediumImpact();
    // Double-tap haptic for distinct processing feel
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.mediumImpact();
    });
    _log('🔔 Earcon: processing');
  }

  /// Play "response ready" chime — AI starts speaking
  void _playResponseEarcon() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
    _log('🔔 Earcon: AI speaking');
  }

  // ═══════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _cameraReady = _initCamera();
  }

  @override
  void dispose() {
    _stopAll();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      _log('No cameras available', 'error');
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
    if (mounted) setState(() {});
    _log('📷 Camera ready (${_cameraController!.value.previewSize})');
  }

  // ═══════════════════════════════════════════════════
  // CONNECT (via AccessibleLiveConnector with VAD config)
  // ═══════════════════════════════════════════════════

  Future<void> _connect() async {
    if (_isConnected) return;
    _log('🔌 Connecting with accessible VAD...');
    final startTime = DateTime.now();

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
        // ★ Blind-accessible VAD tuning
        startOfSpeechSensitivity: 'START_SENSITIVITY_LOW',
        endOfSpeechSensitivity: 'END_SENSITIVITY_LOW',
        silenceDurationMs: 1500, // Allow pause to think
      );

      final session = await connector.connect();
      _session = session;
      _isConnected = true;

      _connectTimeMs = DateTime.now().difference(startTime).inMilliseconds;
      _log(
        '✅ Connected in ${_connectTimeMs}ms (VAD: LOW/LOW, silence: 1500ms)',
      );
      setState(() {});

      // Start receive loop
      _receiveLoop();
    } catch (e, st) {
      _log('❌ Connect error: $e', 'error');
      _log('Stack: $st', 'error');
    }
  }

  // ═══════════════════════════════════════════════════
  // RECEIVE LOOP (with barge-in + echo cancel)
  // ═══════════════════════════════════════════════════

  Future<void> _receiveLoop() async {
    _log('👂 Receive loop started');
    while (_isConnected && _session != null) {
      try {
        await for (final response in _session!.receive()) {
          if (!_isConnected) break;
          _serverMessages++;

          final msg = response.message;

          if (msg is LiveServerContent) {
            // ── Check for interruption (barge-in) ──
            if (msg.interrupted == true) {
              _log('⚡ BARGE-IN: AI interrupted by user', 'success');
              // HARD CUT-OFF: instantly purge audio buffer
              await _audioOutput.stopImmediately();
              _aiIsSpeaking = false;
              _isFirstAudioChunk = true;
              continue;
            }

            final parts = msg.modelTurn?.parts;
            if (parts != null) {
              for (final part in parts) {
                if (part is InlineDataPart && part.mimeType.contains('audio')) {
                  // ── Earcon: first audio chunk = AI starts speaking ──
                  if (_isFirstAudioChunk) {
                    _isFirstAudioChunk = false;
                    _playResponseEarcon();
                    _aiIsSpeaking = true;
                    // Re-init audio output if it was purged by barge-in
                    _audioOutput.init();
                  }

                  _audioChunksReceived++;
                  _audioOutput.addAudioStream(part.bytes);
                  if (_audioChunksReceived % 20 == 0) {
                    _log('🔊 Audio received: $_audioChunksReceived chunks');
                  }
                }
                if (part is TextPart) {
                  _log('💬 ${part.text}');
                }
              }
            }

            // ── Turn complete: AI finished speaking ──
            if (msg.turnComplete == true) {
              _log('✅ Turn complete (msg #$_serverMessages)');
              _aiIsSpeaking = false;
              _isFirstAudioChunk = true;
              _playListeningEarcon(); // "I'm listening again"
            }
          } else if (msg.runtimeType.toString() == 'LiveServerSetupComplete') {
            _log('✅ Setup complete');
            _playListeningEarcon();
          } else {
            if (_serverMessages <= 5) {
              _log('📨 #$_serverMessages: ${msg.runtimeType}');
            }
          }
        }
        if (_isConnected) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (e) {
        if (!_isConnected) break;
        final errMsg = e.toString();
        if (errMsg.contains('Closed')) {
          _log('❌ WebSocket closed', 'error');
          _stopAll();
          break;
        }
        _log('❌ Receive: $errMsg', 'error');
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    _log('👂 Receive loop ended');
  }

  // ═══════════════════════════════════════════════════
  // START ALL
  // ═══════════════════════════════════════════════════

  Future<void> _startAll() async {
    if (!_isConnected) await _connect();
    if (!_isConnected) return;

    await _cameraReady;

    _startAudioStream();
    _startVideoStream();
  }

  // ═══════════════════════════════════════════════════
  // AUDIO (with echo cancellation + PTT support)
  // ═══════════════════════════════════════════════════

  Future<void> _startAudioStream() async {
    if (_isStreamingAudio) return;
    _isStreamingAudio = true;
    _audioChunksSent = 0;
    _audioOutput.init();
    _log('🎤 Mic started (HW AEC: ON, PTT: ${_pushToTalkMode ? "ON" : "OFF"})');

    try {
      final audioStream = await _audioInput.startRecordingStream();
      if (audioStream == null) {
        _log('❌ Mic returned null', 'error');
        _isStreamingAudio = false;
        return;
      }
      audioStream.listen((data) async {
        if (!_isConnected || _session == null) return;

        // Hardware AEC handles echo cancellation — mic stays active
        // so the server can detect user barge-in while AI speaks

        // ── Push-to-Talk: only send when PTT button is held ──
        if (_pushToTalkMode && !_pttPressed) return;

        try {
          await _session!.sendAudioRealtime(
            InlineDataPart('audio/pcm;rate=16000', data),
          );
          _audioChunksSent++;
          if (_audioChunksSent % 100 == 0) {
            _log('🎤 Sent: $_audioChunksSent chunks');
          }
        } catch (e) {
          if (e.toString().contains('Closed')) {
            _isStreamingAudio = false;
          }
        }
      }, onError: (e) => _log('❌ Mic: $e', 'error'));
    } catch (e) {
      _log('❌ Mic start: $e', 'error');
      _isStreamingAudio = false;
    }
  }

  // ═══════════════════════════════════════════════════
  // VIDEO (startImageStream → sendVideoRealtime @ 1 FPS)
  // ═══════════════════════════════════════════════════

  void _startVideoStream() {
    if (_isStreamingVideo) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _log('⚠️ Camera not ready', 'error');
      return;
    }

    _isStreamingVideo = true;
    _videoFramesSent = 0;
    _log('📷 Video: startImageStream → 1 FPS');

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

      _videoFramesSent++;
      if (_videoFramesSent % 5 == 0) {
        _log(
          '📷 Frame #$_videoFramesSent (${(jpegBytes.length / 1024).toStringAsFixed(0)}KB)',
        );
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Closed')) {
        _isStreamingVideo = false;
        return;
      }
      if (!msg.contains('disposed')) {
        _log('⚠️ Frame: $e', 'error');
      }
    } finally {
      _isConvertingFrame = false;
    }
  }

  // ═══════════════════════════════════════════════════
  // SEND TEXT
  // ═══════════════════════════════════════════════════

  Future<void> _sendTextPrompt(String text) async {
    if (!_isConnected || _session == null) {
      _log('⚠️ Not connected');
      return;
    }
    _log('📤 "$text"');
    try {
      await _session!.send(input: Content.text(text), turnComplete: true);
    } catch (e) {
      _log('❌ Send: $e', 'error');
    }
  }

  /// Send ~2s of silence audio so VAD detects end of speech.
  Future<void> _sendSilenceTail() async {
    if (!_isConnected || _session == null) return;
    final silence = Uint8List(3200); // 100ms of silence PCM
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
    _log('🔇 Silence tail sent (VAD should trigger)');
  }

  // ═══════════════════════════════════════════════════
  // STOP
  // ═══════════════════════════════════════════════════

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
    _session?.close();
    _session = null;
    if (mounted) setState(() {});
    _log('🛑 Stopped');
  }

  // ═══════════════════════════════════════════════════
  // BUILD UI
  // ═══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Live (Accessible)', style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // PTT mode toggle
          IconButton(
            icon: Icon(
              _pushToTalkMode ? Icons.touch_app : Icons.mic,
              color: _pushToTalkMode ? Colors.white : Colors.white70,
            ),
            tooltip: _pushToTalkMode ? 'Push-to-Talk ON' : 'Always Listen',
            onPressed: () {
              setState(() => _pushToTalkMode = !_pushToTalkMode);
              _log(
                '🎛️ Mode: ${_pushToTalkMode ? "Push-to-Talk" : "Always Listen"}',
              );
            },
          ),
          // Status badge
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color:
                  _isConnected
                      ? (_aiIsSpeaking ? Colors.white : Colors.white)
                      : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isConnected
                  ? (_aiIsSpeaking
                      ? '🗣️ AI speaking'
                      : '👂 Listening | A:$_audioChunksSent V:$_videoFramesSent')
                  : '🔴 OFF',
              style: const TextStyle(fontSize: 10, color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera preview
          if (_cameraController != null &&
              _cameraController!.value.isInitialized)
            SizedBox(
              height: 180,
              child: Stack(
                children: [
                  Center(child: CameraPreview(_cameraController!)),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'VAD: LOW/LOW | Silence: 1500ms\n'
                        'Echo cancel: ${_aiIsSpeaking ? "MUTED" : "OPEN"}\n'
                        'Mode: ${_pushToTalkMode ? "PTT" : "Auto"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected ? _stopAll : _startAll,
                    icon: Icon(
                      _isConnected ? Icons.stop_circle : Icons.play_circle,
                    ),
                    label: Text(_isConnected ? 'STOP' : 'START'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isConnected ? Colors.white : Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                // Push-to-Talk button (visible when PTT mode is on)
                if (_pushToTalkMode && _isConnected) ...[
                  const SizedBox(width: 8),
                  Listener(
                    // ★ Use raw Listener — GestureDetector's tap/longPress
                    // fight in the gesture arena, causing _pttPressed to
                    // briefly go false (onTapCancel) and drop audio.
                    onPointerDown: (_) {
                      setState(() => _pttPressed = true);
                      _playListeningEarcon();
                      _log('🎤 PTT: SPEAKING');
                    },
                    onPointerUp: (_) {
                      setState(() => _pttPressed = false);
                      _playProcessingEarcon();
                      _log('🎤 PTT: RELEASED → sending silence tail');
                      _sendSilenceTail();
                    },
                    onPointerCancel: (_) {
                      setState(() => _pttPressed = false);
                    },
                    child: Container(
                      width: 120,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _pttPressed ? Colors.white : Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _pttPressed ? Icons.mic : Icons.mic_off,
                              color: Colors.black,
                              size: 28,
                            ),
                            Text(
                              _pttPressed ? 'TALKING' : 'HOLD',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Quick prompts
          if (_isConnected)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  _promptChip('What do you see?'),
                  _promptChip('Any obstacles?'),
                  _promptChip('Read any text'),
                  _promptChip('Describe the scene'),
                ],
              ),
            ),

          // Debug log
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'LOG (${_logEntries.length})',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Clear log',
                        child: GestureDetector(
                          onTap: () => setState(() => _logEntries.clear()),
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      controller: _logScroll,
                      itemCount: _logEntries.length,
                      itemBuilder: (_, i) {
                        final entry = _logEntries[i];
                        Color color;
                        switch (entry.level) {
                          case 'error':
                            color = Colors.white;
                          case 'success':
                            color = Colors.white;
                          default:
                            color = Colors.white70;
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '[${entry.ts}] ${entry.msg}',
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _promptChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 11)),
      onPressed: () => _sendTextPrompt(text),
      backgroundColor: Colors.black,
      labelStyle: const TextStyle(color: Colors.white),
    );
  }
}

class _LogEntry {
  final String ts;
  final String msg;
  final String level;
  _LogEntry(this.ts, this.msg, this.level);
}
