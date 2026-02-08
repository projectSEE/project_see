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
  /// Optionally include database context for contextual responses.
  Future<String> sendMessage(
    String text, {
    Uint8List? imageBytes,
    String? imageMimeType,
    Map<String, dynamic>? databaseContext,
  }) async {
    try {
      // Build system context from database
      String systemContext = '';
      if (databaseContext != null && databaseContext.isNotEmpty) {
        systemContext = _buildSystemContext(databaseContext);
      }
      
      // Combine system context with user message
      final fullPrompt = systemContext.isNotEmpty 
          ? '$systemContext\n\nUser message: ${text.isEmpty ? "Describe this image" : text}'
          : (text.isEmpty ? "Describe this image" : text);
      
      final promptParts = <Part>[TextPart(fullPrompt)];

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
  
  /// Build system context string from database context.
  String _buildSystemContext(Map<String, dynamic> context) {
    final buffer = StringBuffer();
    buffer.writeln('You are a helpful accessibility assistant. Use the following context to provide personalized responses:');
    buffer.writeln();
    
    // Accessibility settings
    final settingsValue = context['accessibilitySettings'];
    if (settingsValue != null && settingsValue is Map) {
      buffer.writeln('User Accessibility Preferences:');
      if (settingsValue['visualImpairment'] == true) {
        buffer.writeln('- User has visual impairment. Provide detailed audio descriptions.');
      }
      if (settingsValue['hearingImpairment'] == true) {
        buffer.writeln('- User has hearing impairment. Avoid audio-only instructions.');
      }
      if (settingsValue['mobilityImpairment'] == true) {
        buffer.writeln('- User has mobility impairment. Prioritize accessible routes and facilities.');
      }
      buffer.writeln();
    }
    
    // Recent conversations
    final convosValue = context['recentConversations'];
    if (convosValue != null && convosValue is List) {
      final convos = convosValue;
      if (convos.isNotEmpty) {
        buffer.writeln('Recent conversation context:');
        for (final conv in convos.take(5)) {
          if (conv is Map) {
            final role = conv['role']?.toString() ?? 'unknown';
            final content = conv['content']?.toString() ?? '';
            buffer.writeln('- $role: $content');
          }
        }
        buffer.writeln();
      }
    }
    
    // Nearby POIs
    final poisValue = context['nearbyPOIs'];
    if (poisValue != null && poisValue is List) {
      final pois = poisValue;
      if (pois.isNotEmpty) {
        buffer.writeln('Nearby accessible locations:');
        for (final poi in pois.take(5)) {
          if (poi is Map) {
            buffer.writeln('- ${poi['name']} (${poi['type']}): ${poi['description']}');
            final safetyNotes = poi['safetyNotes'];
            if (safetyNotes != null && safetyNotes.toString().isNotEmpty) {
              buffer.writeln('  Safety: $safetyNotes');
            }
          }
        }
        buffer.writeln();
      }
    }
    
    return buffer.toString();
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
    
    await _session!.sendMediaChunks(mediaChunks: [InlineDataPart('audio/pcm', audioData)]);
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