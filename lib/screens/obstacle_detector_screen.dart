import 'package:flutter/material.dart';
import '../services/tts_service.dart';
import 'object_detection_screen.dart';
import 'live_screen.dart';
import 'live_test_screen.dart';
import 'navigation_screen.dart';
import '../core/localization/app_localizations.dart';
import '../core/services/language_provider.dart';

/// Obstacle Detector Hub — 3 large buttons to navigate to
/// Object Detection, Live Assistant, and Navigation screens.
class ObstacleDetectorScreen extends StatefulWidget {
  const ObstacleDetectorScreen({super.key});

  @override
  State<ObstacleDetectorScreen> createState() => _ObstacleDetectorScreenState();
}

class _ObstacleDetectorScreenState extends State<ObstacleDetectorScreen> {
  final TTSService _ttsService = TTSService();
  final LanguageNotifier _langNotifier = LanguageNotifier();

  @override
  void initState() {
    super.initState();
    _langNotifier.addListener(_onLangChanged);
    _init();
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await _ttsService.initialize();
    final strings = AppLocalizations(_langNotifier.languageCode);
    await _ttsService.speak(strings.get('obstacleDetectorMenuTts'));
  }

  @override
  void dispose() {
    _langNotifier.removeListener(_onLangChanged);
    _ttsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations(_langNotifier.languageCode);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // Header
              const SizedBox(height: 8),
              Semantics(
                header: true,
                child: Text(
                  strings.get('obstacleDetectorHub'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                strings.get('chooseAFeature'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 32),

              // —— 1. OBJECT DETECTION ——
              _buildFeatureButton(
                icon: Icons.remove_red_eye_rounded,
                label: strings.get('objectDetection'),
                subtitle: strings.get('objectDetectionSubtitle'),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shadowColor: Colors.blue.withValues(alpha: 0.35),
                semanticLabel: strings.get('objectDetectionSemantic'),
                onTap: () {
                  _ttsService.speak(strings.get('openingObjectDetection'));
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ObjectDetectionScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // —— 2. LIVE ASSISTANT ——
              _buildFeatureButton(
                icon: Icons.videocam_rounded,
                label: strings.get('liveAssistant'),
                subtitle: strings.get('liveAssistantSubtitle'),
                gradient: const LinearGradient(
                  colors: [Color(0xFFC62828), Color(0xFFEF5350)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shadowColor: Colors.red.withValues(alpha: 0.35),
                semanticLabel: strings.get('liveAssistantSemantic'),
                onTap: () {
                  _ttsService.speak(strings.get('openingLiveAssistant'));
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LiveScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),

              // —— 2b. LIVE TEST (DEBUG) ——
              _buildFeatureButton(
                icon: Icons.bug_report_rounded,
                label: strings.get('liveTest'),
                subtitle: strings.get('liveTestSubtitle'),
                gradient: const LinearGradient(
                  colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shadowColor: Colors.orange.withValues(alpha: 0.35),
                semanticLabel: strings.get('liveTestSemantic'),
                onTap: () {
                  _ttsService.speak(strings.get('openingLiveTest'));
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LiveTestScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),

              // —— 3. NAVIGATION ——
              _buildFeatureButton(
                icon: Icons.navigation_rounded,
                label: strings.get('navigate'),
                subtitle: strings.get('navigateSubtitle'),
                gradient: const LinearGradient(
                  colors: [Color(0xFF00695C), Color(0xFF26A69A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shadowColor: Colors.teal.withValues(alpha: 0.35),
                semanticLabel: strings.get('navigateSemantic'),
                onTap: () {
                  _ttsService.speak(strings.get('openingNavigation'));
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NavigationScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Back button
              Semantics(
                button: true,
                label: strings.get('goBackHome'),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.arrow_back,
                            color: Colors.white70,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            strings.get('back').toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Gradient gradient,
    required Color shadowColor,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 48),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
