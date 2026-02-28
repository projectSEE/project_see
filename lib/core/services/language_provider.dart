import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/tts_service.dart';

/// Language notifier — follows the same ChangeNotifier pattern
/// as development's ThemeNotifier for consistency.
class LanguageNotifier extends ChangeNotifier {
  static final LanguageNotifier _instance = LanguageNotifier._internal();
  factory LanguageNotifier() => _instance;
  LanguageNotifier._internal();

  static const String _languageKey = 'app_language';

  String _languageCode = 'en';
  String get languageCode => _languageCode;

  /// Available languages with display names
  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'zh': '中文',
    'ms': 'Bahasa Melayu',
    'ta': 'தமிழ்',
  };

  /// Load persisted language on startup
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _languageCode = prefs.getString(_languageKey) ?? 'en';

      // Sync initial language to TTS immediately
      await TTSService().setAppLanguage(_languageCode);

      notifyListeners();
    } catch (e) {
      debugPrint('LanguageNotifier: init error: $e');
    }
  }

  /// Change the app language and persist
  Future<void> setLanguage(String code) async {
    if (code == _languageCode) return;
    _languageCode = code;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, code);
      // Immediately tell TTSService there's a new language so reading/STT behaves appropriately
      await TTSService().setAppLanguage(code);
    } catch (e) {
      debugPrint('LanguageNotifier: save error: $e');
    }
  }
}
