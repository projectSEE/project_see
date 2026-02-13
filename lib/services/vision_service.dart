import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

class VisionService {
  // 🔴 TODO: PASTE YOUR GEMINI API KEY HERE
  static const String _apiKey = 'AIzaSyDf7hsxUJUCCy_6bu8haQrCe2TaxlaK9IU';

  late final GenerativeModel _model;

  VisionService() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash', // Flash is faster/cheaper for video
      apiKey: _apiKey,
    );
  }

  Future<Map<String, dynamic>> analyzeImage(String imagePath) async {
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) return {};

    final imageBytes = await imageFile.readAsBytes();

    // The Prompt: We force the AI to return JSON so the app can read it
    final prompt = TextPart("""
      You are a Guardian AI. Analyze this image for immediate physical threats 
      (e.g., fire, person falling, weapon, car crash, violence).
      Return ONLY valid JSON with no markdown formatting:
      {
        "danger": true/false,
        "reason": "short explanation (max 5 words)"
      }
    """);

    final imagePart = DataPart('image/jpeg', imageBytes);

    try {
      final response = await _model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      // Clean the response (sometimes AI adds ```json ... ``` wrappers)
      final text = response.text?.replaceAll('```json', '').replaceAll('```', '').trim();
      print("AI RAW RESPONSE: $text"); 

      return jsonDecode(text ?? '{}');
    } catch (e) {
      print("AI Vision Error: $e");
      return {"danger": false, "error": e.toString()};
    }
  }
}