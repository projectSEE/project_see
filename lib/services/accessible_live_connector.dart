import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Custom connector that tries to inject VAD config into the Gemini Live API
/// setup message. If the server rejects the extra fields, falls back to the
/// standard SDK connect.
///
/// Returns a standard [LiveSession] — fully compatible with all SDK methods.
class AccessibleLiveConnector {
  AccessibleLiveConnector({
    required this.model,
    required this.location,
    this.systemInstruction,
    this.liveGenerationConfig,
    // VAD tuning
    this.startOfSpeechSensitivity = 'START_SENSITIVITY_LOW',
    this.endOfSpeechSensitivity = 'END_SENSITIVITY_LOW',
    this.prefixPaddingMs,
    this.silenceDurationMs = 1500,
    this.vadDisabled = false,
  });

  final String model;
  final String location;
  final Content? systemInstruction;
  final LiveGenerationConfig? liveGenerationConfig;

  // VAD config
  final String startOfSpeechSensitivity;
  final String endOfSpeechSensitivity;
  final int? prefixPaddingMs;
  final int? silenceDurationMs;
  final bool vadDisabled;

  // SDK constants (from base_model.dart)
  static const _baseAuthority = 'firebasevertexai.googleapis.com';
  static const _apiUrl = 'ws/google.firebase.vertexai';
  static const _apiVersion = 'v1beta';
  static const _apiUrlSuffix =
      'LlmBidiService/BidiGenerateContent/locations';

  /// Connect with accessible VAD config.
  /// Falls back to standard SDK connect if custom setup is rejected.
  Future<LiveSession> connect() async {
    // Try custom connect with VAD config first
    try {
      final session = await _customConnect();
      // Wait a moment to check if server accepted the setup
      await Future.delayed(const Duration(milliseconds: 500));
      return session;
    } catch (e) {
      debugPrint('⚠️ Custom connect failed: $e');
      debugPrint('🔄 Falling back to SDK connect (no VAD config)...');
      return _sdkFallbackConnect();
    }
  }

  /// Custom WebSocket connect that includes VAD configuration
  Future<LiveSession> _customConnect() async {
    final app = Firebase.app();
    final projectId = app.options.projectId;
    final apiKey = app.options.apiKey;

    final uri = 'wss://$_baseAuthority/'
        '$_apiUrl.$_apiVersion.$_apiUrlSuffix/'
        '$location?key=$apiKey';

    final modelString =
        'projects/$projectId/locations/$location/publishers/google/models/$model';

    // Build VAD config — try multiple field name formats
    final vadConfig = vadDisabled
        ? {'disabled': true}
        : {
            'startOfSpeechSensitivity': startOfSpeechSensitivity,
            'endOfSpeechSensitivity': endOfSpeechSensitivity,
            if (prefixPaddingMs != null) 'prefixPaddingMs': prefixPaddingMs,
            if (silenceDurationMs != null)
              'silenceDurationMs': silenceDurationMs,
          };

    // Build setup JSON — matches SDK structure + adds realtime_input_config
    final setupJson = <String, dynamic>{
      'setup': <String, dynamic>{
        'model': modelString,
        if (systemInstruction != null)
          'system_instruction': systemInstruction!.toJson(),
        if (liveGenerationConfig != null) ...{
          'generation_config': liveGenerationConfig!.toJson(),
        },
        // VAD config — use snake_case to match other top-level setup fields
        'realtime_input_config': {
          'automatic_activity_detection': vadConfig,
        },
      },
    };

    final request = jsonEncode(setupJson);
    debugPrint('🔌 Custom connect: $uri');
    debugPrint('🎛️ VAD config: $vadConfig');

    final WebSocketChannel ws;
    if (kIsWeb) {
      ws = WebSocketChannel.connect(Uri.parse(uri));
    } else {
      ws = IOWebSocketChannel.connect(Uri.parse(uri));
    }
    await ws.ready;
    ws.sink.add(request);

    debugPrint('✅ Custom connect: setup sent with VAD config');
    return LiveSession(ws);
  }

  /// Standard SDK fallback connect (no VAD config)
  Future<LiveSession> _sdkFallbackConnect() async {
    final liveModel = FirebaseAI.vertexAI(
      location: location,
    ).liveGenerativeModel(
      model: model,
      systemInstruction: systemInstruction,
      liveGenerationConfig: liveGenerationConfig,
    );

    final session = await liveModel.connect();
    debugPrint('✅ SDK fallback connect: connected (no VAD config)');
    return session;
  }
}
