import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_ai/firebase_ai.dart';

/// Service for Gemini AI scene description via Firebase AI
class GeminiService {
  GenerativeModel? _model;
  ChatSession? _chat;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isLiveMode = false;

  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;
  bool get isLiveMode => _isLiveMode;

  /// Initialize Gemini via Firebase AI
  Future<void> initialize() async {
    try {
      _model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.0-flash',
        generationConfig: GenerationConfig(
          temperature: 0.7,
          maxOutputTokens: 300,
        ),
        systemInstruction: Content.system('''
You are a helpful AI assistant for blind people navigating the real world.
Your role is like a caring companion who helps them understand their surroundings.
Keep responses SHORT (1-3 sentences), clear, and actionable.
Focus on safety-relevant information: obstacles, hazards, paths, signs, and people.
When asked questions, answer directly and helpfully.
If you see text or signs, read them out loud.
Speak naturally, as if you're a friend walking beside them.
'''),
      );
      _isInitialized = true;
      debugPrint('✅ Gemini AI (Firebase AI) initialized');
    } catch (e) {
      debugPrint('❌ Gemini init error: $e');
      _isInitialized = false;
    }
  }

  /// Start live mode - creates a chat session for continuous conversation
  void startLiveMode() {
    if (_model != null) {
      _chat = _model!.startChat();
      _isLiveMode = true;
      debugPrint('🟢 Gemini Live mode started');
    }
  }

  /// Stop live mode
  void stopLiveMode() {
    _chat = null;
    _isLiveMode = false;
    debugPrint('🔴 Gemini Live mode stopped');
  }

  /// Describe scene from image file path
  Future<String> describeScene(String imagePath) async {
    if (!_isInitialized || _model == null) {
      return 'Gemini AI is not initialized.';
    }
    
    if (_isProcessing) {
      return 'Still processing previous request...';
    }
    
    _isProcessing = true;
    
    try {
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      
      final prompt = TextPart('''
Describe what you see in this image in 1-2 short sentences for a blind person.
Focus on obstacles, hazards, walking path, and important objects.
''');
      
      final imagePart = InlineDataPart('image/jpeg', imageBytes);
      
      final response = await _model!.generateContent([
        Content.multi([prompt, imagePart])
      ]);
      
      final text = response.text ?? 'Could not describe the scene.';
      
      debugPrint('🤖 Gemini response: $text');
      return text;
    } catch (e) {
      debugPrint('❌ Gemini error: $e');
      return 'Error describing scene: ${e.toString()}';
    } finally {
      _isProcessing = false;
    }
  }

  /// Ask a question about what the camera sees (Live mode)
  Future<String> askQuestion(String imagePath, String question) async {
    if (!_isInitialized || _model == null) {
      return 'Gemini AI is not initialized.';
    }
    
    if (_isProcessing) {
      return 'Please wait...';
    }
    
    _isProcessing = true;
    
    try {
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      
      final prompt = TextPart('Question from blind user: $question');
      final imagePart = InlineDataPart('image/jpeg', imageBytes);
      
      GenerateContentResponse response;
      
      if (_isLiveMode && _chat != null) {
        // Use chat session for context
        response = await _chat!.sendMessage(
          Content.multi([prompt, imagePart])
        );
      } else {
        // Single request
        response = await _model!.generateContent([
          Content.multi([prompt, imagePart])
        ]);
      }
      
      final text = response.text ?? 'I could not understand the scene.';
      
      debugPrint('🤖 Gemini Q&A: $text');
      return text;
    } catch (e) {
      debugPrint('❌ Gemini error: $e');
      return 'Error: ${e.toString()}';
    } finally {
      _isProcessing = false;
    }
  }

  /// Quick text-only question (for follow-up questions without new image)
  Future<String> askFollowUp(String question) async {
    if (!_isLiveMode || _chat == null) {
      return 'Please start live mode first.';
    }
    
    if (_isProcessing) {
      return 'Please wait...';
    }
    
    _isProcessing = true;
    
    try {
      final response = await _chat!.sendMessage(
        Content.text(question)
      );
      
      return response.text ?? 'I did not understand.';
    } catch (e) {
      debugPrint('❌ Gemini error: $e');
      return 'Error: ${e.toString()}';
    } finally {
      _isProcessing = false;
    }
  }

  void dispose() {
    stopLiveMode();
  }
}
