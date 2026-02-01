import 'dart:typed_data';
import 'dart:convert';
import 'package:firebase_vertexai/firebase_vertexai.dart';

class HazardService {
  // Ignore the deprecation warning for the Hackathon (It is just a name change)
  final model = FirebaseVertexAI.instance.generativeModel(
    model: 'gemini-1.5-flash',
    generationConfig: GenerationConfig(responseMimeType: 'application/json'),
  );

  Future<Map<String, dynamic>> detectDanger(Uint8List imageBytes) async {
    // FIX: Use 'Content.multi' and 'InlineDataPart' instead of Content.data
    final prompt = Content.multi([
      TextPart(
        "Analyze this image for immediate hazards to a blind person. "
        "Look specifically for: 'Yellow Tactile Paving', 'Train Platform Edge', 'Construction Holes', 'Traffic Cones'. "
        "Return strictly this JSON format: "
        "{ \"danger\": true/false, \"type\": \"hazard_name\", \"action\": \"STOP\" or \"None\" }"
      ),
      InlineDataPart('image/jpeg', imageBytes),
    ]);

    try {
      final response = await model.generateContent([prompt]);
      final text = response.text;
      
      if (text != null) {
        // Clean and parse JSON
        final cleanText = text.replaceAll('```json', '').replaceAll('```', '');
        return jsonDecode(cleanText); 
      }
    } catch (e) {
      // ignore: avoid_print
      print("AI Error: $e");
    }
    return {"danger": false, "type": "Unknown", "action": "None"};
  }
}