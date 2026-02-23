import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_ai/firebase_ai.dart';

/// Service for Gemini Live API - Real-time audio/video conversation
/// Based on official Flutter demo: https://github.com/flutter/demos/tree/main/firebase_ai_logic_showcase/lib/demos/live_api
class GeminiLiveService {
  LiveSession? _session;
  bool _liveSessionIsOpen = false;
  bool _isInitialized = false;
  StringBuffer _textAccumulator = StringBuffer();  // Accumulate text across responses
  
  // Callbacks
  Function(String)? onResponse;
  Function(Uint8List)? onAudioResponse;
  Function(String)? onError;
  Function()? onReady;
  
  bool get isConnected => _liveSessionIsOpen;
  bool get isInitialized => _isInitialized;

  /// Create the live model using Vertex AI with specific location
  /// Configured for audio output - Gemini speaks directly!
  late final LiveGenerativeModel _liveModel = FirebaseAI.vertexAI(
    location: 'us-central1',
  ).liveGenerativeModel(
    model: 'gemini-live-2.5-flash-native-audio',
    systemInstruction: Content.text('''
You are a vision assistant for blind users. Your job is to be their eyes.

Response rules:
1. Use directions: ahead, left, right, above, below
2. Estimate distances: very close (within 1m), close (3m), medium (5m), far (10m+)
3. Prioritize hazards: stairs, steps, vehicles, obstacles, holes
4. Keep each response under 20 words, be concise
5. Speak clearly and at a moderate pace
6. Focus on what matters for safe navigation

Example responses:
- "Clear path ahead, about 5 meters"
- "Person approaching from your left"
- "Door ahead on the left, you can proceed"
- "Caution, car ahead"
'''),
    liveGenerationConfig: LiveGenerationConfig(
      // Request AUDIO response - Gemini will speak directly!
      responseModalities: [ResponseModalities.audio],
      speechConfig: SpeechConfig(
        voiceName: 'Puck',  // Clear English voice
      ),
    ),
  );

  /// Initialize service
  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('✅ Gemini Live API initialized (Audio Mode)');
  }

  /// Connect to live session
  Future<void> connect() async {
    if (_liveSessionIsOpen) return;
    
    try {
      _session = await _liveModel.connect();
      _liveSessionIsOpen = true;
      debugPrint('🟢 Gemini Live session connected');
      
      // Start processing messages in the background
      unawaited(_processMessagesContinuously());
    } catch (e) {
      debugPrint('❌ Connect error: $e');
      onError?.call('Failed to connect: $e');
    }
  }

  /// Close the live session
  Future<void> close() async {
    if (!_liveSessionIsOpen) return;
    try {
      await _session?.close();
    } catch (e) {
      debugPrint('❌ Close error: $e');
    } finally {
      _liveSessionIsOpen = false;
    }
  }

  /// Send audio/video stream using sendMediaStream (matching official demo)
  void sendMediaStream(Stream<InlineDataPart> stream) {
    if (!_liveSessionIsOpen || _session == null) return;
    _session!.sendMediaStream(stream);
  }

  /// Start audio streaming
  void startAudioStream(Stream<Uint8List> audioStream) {
    if (!_liveSessionIsOpen || _session == null) return;
    
    debugPrint('🎤 Starting audio stream to Gemini...');
    
    // Convert audio bytes to InlineDataPart stream
    sendMediaStream(audioStream.map((data) {
      return InlineDataPart('audio/pcm', data);
    }));
  }

  /// Start video streaming (1 fps image stream)
  void startVideoStream(Stream<Uint8List> imageStream) {
    if (!_liveSessionIsOpen || _session == null) return;
    
    debugPrint('📷 Starting video stream to Gemini...');
    
    sendMediaStream(imageStream.map((data) {
      return InlineDataPart('image/jpeg', data);
    }));
  }

  /// Send a single image frame
  Future<void> sendImage(Uint8List imageData) async {
    if (!_liveSessionIsOpen || _session == null) return;
    
    try {
      debugPrint('📷 Sending image (${imageData.length} bytes)');
      _session!.send(
        input: Content.multi([InlineDataPart('image/jpeg', imageData)]),
        turnComplete: false,
      );
    } catch (e) {
      debugPrint('❌ Send image error: $e');
    }
  }

  /// Send text message
  void sendText(String text) {
    if (!_liveSessionIsOpen || _session == null) {
      onError?.call('Not connected');
      return;
    }
    
    try {
      debugPrint('📤 Sent: $text');
      _session!.send(
        input: Content.text(text),
        turnComplete: true,
      );
    } catch (e) {
      debugPrint('❌ Send text error: $e');
      onError?.call('Failed to send: $e');
    }
  }

  /// Process incoming messages continuously (matching official demo pattern)
  Future<void> _processMessagesContinuously() async {
    debugPrint('👂 Starting to listen for Gemini responses...');
    int responseCount = 0;
    
    try {
      await for (final response in _session!.receive()) {
        responseCount++;
        final message = response.message;
        debugPrint('📨 Response #$responseCount: ${message.runtimeType}');
        await _handleMessage(message);
      }
      log('Live session receive stream completed normally after $responseCount responses.');
    } catch (e, stackTrace) {
      log('❌ Error receiving messages: $e');
      log('Stack trace: $stackTrace');
      onError?.call('Receive error: $e');
    } finally {
      _liveSessionIsOpen = false;
      debugPrint('🔴 Live session ended (total: $responseCount responses)');
    }
  }

  /// Handle different message types
  Future<void> _handleMessage(LiveServerMessage message) async {
    // Handle setup complete  
    if (message.runtimeType.toString() == 'LiveServerSetupComplete') {
      debugPrint('✅ Setup complete - ready to send data!');
      onReady?.call();
      return;
    }
    
    if (message is LiveServerContent) {
      await _handleContent(message);
    } else if (message is LiveServerToolCall) {
      debugPrint('📞 Tool call received');
    }
  }

  /// Handle content from model - accumulate text across multiple responses
  Future<void> _handleContent(LiveServerContent content) async {
    final modelTurn = content.modelTurn;
    if (modelTurn != null) {
      debugPrint('📨 ModelTurn parts count: ${modelTurn.parts.length}');
      
      for (final part in modelTurn.parts) {
        debugPrint('📦 Part type: ${part.runtimeType}');
        
        if (part is TextPart) {
          _textAccumulator.write(part.text);
          debugPrint('📝 Text chunk: ${part.text}');
        } else if (part is InlineDataPart) {
          debugPrint('📦 InlineDataPart mimeType: ${part.mimeType}, bytes: ${part.bytes.length}');
          if (part.mimeType.startsWith('audio')) {
            debugPrint('🔊 AUDIO RECEIVED! (${part.bytes.length} bytes, mimeType: ${part.mimeType})');
            if (onAudioResponse != null) {
              debugPrint('🔊 Calling onAudioResponse callback...');
              onAudioResponse!(part.bytes);
            } else {
              debugPrint('⚠️ onAudioResponse callback is NULL!');
            }
          }
        } else {
          debugPrint('❓ Unknown part type: ${part.runtimeType}');
        }
      }
    } else {
      debugPrint('⚠️ ModelTurn is null');
    }
    
    // Send complete text response when turn is complete
    if (content.turnComplete == true) {
      if (_textAccumulator.isNotEmpty) {
        final text = _textAccumulator.toString();
        debugPrint('🤖 Gemini Live: $text');
        onResponse?.call(text);
        _textAccumulator.clear();  // Reset for next turn
      }
      debugPrint('✅ Turn complete');
    }
  }

  /// Disconnect from live session
  Future<void> disconnect() async {
    await close();
    debugPrint('🔴 Gemini Live disconnected');
  }

  void dispose() {
    unawaited(close());
  }
}
