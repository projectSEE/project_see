import 'package:flutter/material.dart';
import '../services/tts_service.dart';
import 'object_detection_screen.dart';
import 'live_screen.dart';
import 'live_test_screen.dart';
import 'navigation_screen.dart';

/// Obstacle Detector Hub — 3 large buttons to navigate to
/// Object Detection, Live Assistant, and Navigation screens.
class ObstacleDetectorScreen extends StatefulWidget {
  const ObstacleDetectorScreen({super.key});

  @override
  State<ObstacleDetectorScreen> createState() => _ObstacleDetectorScreenState();
}

class _ObstacleDetectorScreenState extends State<ObstacleDetectorScreen> {
  final TTSService _ttsService = TTSService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _ttsService.initialize();
    await _ttsService.speak(
      'Obstacle detector menu. '
      'Three options available: Object Detection, Live Assistant, and Navigation.',
    );
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // Header
              const SizedBox(height: 8),
              Semantics(
                header: true,
                child: const Text(
                  'Obstacle Detector',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a feature',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 32),

              // ── 1. OBJECT DETECTION ──
              Expanded(
                child: _buildFeatureButton(
                  icon: Icons.remove_red_eye_rounded,
                  label: 'OBJECT DETECTION',
                  subtitle: 'Detect obstacles with camera & haptic feedback',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shadowColor: Colors.blue.withValues(alpha: 0.35),
                  semanticLabel: 'Object Detection. Detect obstacles using camera with haptic and voice feedback.',
                  onTap: () {
                    _ttsService.speak('Opening object detection');
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ObjectDetectionScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── 2. LIVE ASSISTANT ──
              Expanded(
                child: _buildFeatureButton(
                  icon: Icons.videocam_rounded,
                  label: 'LIVE',
                  subtitle: 'Real-time AI assistant with voice & camera',
                  gradient: const LinearGradient(
                    colors: [Color(0xFFC62828), Color(0xFFEF5350)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shadowColor: Colors.red.withValues(alpha: 0.35),
                  semanticLabel: 'Live Assistant. Start a real-time conversation with Gemini AI using voice and camera.',
                  onTap: () {
                    _ttsService.speak('Opening live assistant');
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LiveScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── 2b. LIVE TEST (DEBUG) ──
              Expanded(
                child: _buildFeatureButton(
                  icon: Icons.bug_report_rounded,
                  label: 'LIVE TEST',
                  subtitle: 'Debug Live API step by step',
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shadowColor: Colors.orange.withValues(alpha: 0.35),
                  semanticLabel: 'Live Test. Debug the Gemini Live API step by step.',
                  onTap: () {
                    _ttsService.speak('Opening live test');
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LiveTestScreen()),
                    );
                  },
                ),
              ),

              // ── 3. NAVIGATION ──
              Expanded(
                child: _buildFeatureButton(
                  icon: Icons.navigation_rounded,
                  label: 'NAVIGATE',
                  subtitle: 'Voice-guided walking directions',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00695C), Color(0xFF26A69A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shadowColor: Colors.teal.withValues(alpha: 0.35),
                  semanticLabel: 'Navigate. Get voice-guided walking directions to a destination.',
                  onTap: () {
                    _ttsService.speak('Opening navigation');
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NavigationScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Back button
              Semantics(
                button: true,
                label: 'Go back to home screen',
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.arrow_back, color: Colors.white70, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'BACK',
                            style: TextStyle(
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
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                Text(
                  label,
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
      ),
    );
  }
}
