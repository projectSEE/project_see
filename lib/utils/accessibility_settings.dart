import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accessibility settings utility class.
/// Can be used by a Settings page to configure accessibility features.
class AccessibilitySettings {
  static const String _ttsSpeechRateKey = 'tts_speech_rate';
  static const String _fontScaleKey = 'font_scale';
  static const String _hapticFeedbackKey = 'haptic_feedback_enabled';
  static const String _sttEnabledKey = 'stt_enabled';

  // Default values
  static const double defaultSpeechRate = 0.5;
  static const double defaultFontScale = 1.0;
  static const bool defaultHapticEnabled = true;
  static const bool defaultSttEnabled = false;

  // ============== TTS Speed Control ==============
  
  /// Get current TTS speech rate (0.0 - 1.0)
  static Future<double> getTtsSpeechRate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_ttsSpeechRateKey) ?? defaultSpeechRate;
  }

  /// Set TTS speech rate (0.0 - 1.0)
  static Future<void> setTtsSpeechRate(double rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ttsSpeechRateKey, rate.clamp(0.0, 1.0));
  }

  /// Apply speech rate to FlutterTts instance
  static Future<void> applyTtsSettings(FlutterTts tts) async {
    final rate = await getTtsSpeechRate();
    await tts.setSpeechRate(rate);
  }

  // ============== Font Size Control ==============

  /// Get current font scale multiplier (0.8 - 2.0)
  static Future<double> getFontScale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_fontScaleKey) ?? defaultFontScale;
  }

  /// Set font scale multiplier (0.8 - 2.0)
  static Future<void> setFontScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, scale.clamp(0.8, 2.0));
  }

  // ============== Haptic Feedback ==============

  /// Check if haptic feedback is enabled
  static Future<bool> isHapticFeedbackEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hapticFeedbackKey) ?? defaultHapticEnabled;
  }

  /// Enable/disable haptic feedback
  static Future<void> setHapticFeedbackEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticFeedbackKey, enabled);
  }

  /// Trigger haptic feedback if enabled
  static Future<void> triggerHaptic({HapticType type = HapticType.light}) async {
    final enabled = await isHapticFeedbackEnabled();
    if (!enabled) return;

    switch (type) {
      case HapticType.light:
        await HapticFeedback.lightImpact();
        break;
      case HapticType.medium:
        await HapticFeedback.mediumImpact();
        break;
      case HapticType.heavy:
        await HapticFeedback.heavyImpact();
        break;
      case HapticType.selection:
        await HapticFeedback.selectionClick();
        break;
    }
  }

  // ============== Speech-to-Text ==============

  /// Check if STT input is enabled
  static Future<bool> isSttEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sttEnabledKey) ?? defaultSttEnabled;
  }

  /// Enable/disable STT input
  static Future<void> setSttEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sttEnabledKey, enabled);
  }

  // ============== Reset All Settings ==============

  /// Reset all accessibility settings to defaults
  static Future<void> resetToDefaults() async {
    await setTtsSpeechRate(defaultSpeechRate);
    await setFontScale(defaultFontScale);
    await setHapticFeedbackEnabled(defaultHapticEnabled);
    await setSttEnabled(defaultSttEnabled);
  }
}

/// Types of haptic feedback
enum HapticType {
  light,
  medium,
  heavy,
  selection,
}
