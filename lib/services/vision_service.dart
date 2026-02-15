import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

class VisionService {
  // Your provided Gemini API Key
  static const String _apiKey = 'AIzaSyDf7hsxUJUCCy_6bu8haQrCe2TaxlaK9IU';
  
  final GenerativeModel _model;

  VisionService()
      : _model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: _apiKey,
        );

  /// Sends an image to Gemini to describe obstacles or surroundings
  Future<String> describeImage(Uint8List imageBytes, String prompt) async {
    try {
      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      final response = await _model.generateContent(content);
      return response.text ?? 'No description available.';
    } catch (e) {
      return 'Error analyzing image: $e';
    }
  }

  /// Specialized method for obstacle detection
  Future<String> detectObstacles(Uint8List imageBytes) async {
    const obstaclePrompt = 
        'Identify any obstacles or hazards in this image for a visually impaired person. '
        'Be concise and mention the distance if possible.';
    return describeImage(imageBytes, obstaclePrompt);
  }
}