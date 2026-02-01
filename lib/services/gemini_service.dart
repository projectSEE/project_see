import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_ai/firebase_ai.dart';

/// GeminiService with support for both normal chat and Live API streaming.
class GeminiService {
  late GenerativeModel _model;
  LiveGenerativeModel? _liveModel;
  LiveSession? _session;
  bool _isLiveSessionActive = false;

  GeminiService() {
    // Initialize the normal model using firebase_ai package
    _model = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.5-flash-lite',
    );
  }

  /// Initialize the Live model for real-time audio streaming.
  /// Uses Vertex AI with us-central1 location (required for Live API).
  void initializeLiveModel() {
    _liveModel = FirebaseAI.vertexAI(location: 'us-central1').liveGenerativeModel(
      model: 'gemini-live-2.5-flash-native-audio',
      liveGenerationConfig: LiveGenerationConfig(
        responseModalities: [ResponseModalities.audio],
        speechConfig: SpeechConfig(voiceName: 'Kore'),
      ),
    );
  }

  /// Send a text/image message using the normal (non-live) API.
  Future<String> sendMessage(String text, {Uint8List? imageBytes, String? imageMimeType}) async {
    try {
      final promptParts = <Part>[TextPart(text.isEmpty ? "Describe this image" : text)];

      if (imageBytes != null) {
        promptParts.add(InlineDataPart(imageMimeType ?? 'image/jpeg', imageBytes));
      }

      final content = [Content.multi(promptParts)];
      final response = await _model.generateContent(content);

      return response.text ?? "I could not understand that.";
    } catch (e) {
      print("Gemini Firebase Error: $e");
      return "Error communicating with AI service: $e";
    }
  }

  // ========== Live API Methods ==========

  /// Connect to the Live API session.
  Future<void> connectLive() async {
    if (_liveModel == null) {
      initializeLiveModel();
    }
    
    if (_session != null) {
      await disconnectLive();
    }

    _session = await _liveModel!.connect();
    _isLiveSessionActive = true;
  }

  /// Disconnect from the Live API session.
  Future<void> disconnectLive() async {
    if (_session != null) {
      await _session!.close();
      _session = null;
      _isLiveSessionActive = false;
    }
  }

  /// Send audio data in real-time during a live session.
  Future<void> sendAudioRealtime(Uint8List audioData) async {
    if (_session == null || !_isLiveSessionActive) {
      throw Exception('Live session not active. Call connectLive() first.');
    }
    
    await _session!.sendAudioRealtime(InlineDataPart('audio/pcm', audioData));
  }

  /// Start streaming audio from a stream of audio data.
  Future<void> sendMediaStream(Stream<InlineDataPart> mediaStream) async {
    if (_session == null || !_isLiveSessionActive) {
      throw Exception('Live session not active. Call connectLive() first.');
    }
    
    await _session!.sendMediaStream(mediaStream);
  }

  /// Get the stream of responses from the Live API.
  Stream<LiveServerResponse>? get liveResponses {
    return _session?.receive();
  }

  /// Check if live session is active.
  bool get isLiveSessionActive => _isLiveSessionActive;

  /// Get the current session (for advanced usage).
  LiveSession? get session => _session;
}