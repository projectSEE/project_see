import 'dart:async';
import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'screens/object_detection_screen.dart';
import 'screens/live_screen.dart';
import 'screens/navigation_screen.dart';
import 'theme/theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
// import 'package:url_launcher/url_launcher.dart'; // No longer needed for calls
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:just_audio/just_audio.dart';
import 'screens/awareness_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'core/localization/app_localizations.dart';
import 'core/services/language_provider.dart';
import 'utils/accessibility_settings.dart';
import 'services/tts_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await LanguageNotifier().initialize();
  await TextScaleNotifier().initialize();

  runApp(const VisualAssistantApp());
}

class ThemeNotifier extends ChangeNotifier {
  static final ThemeNotifier _instance = ThemeNotifier._internal();
  factory ThemeNotifier() => _instance;
  ThemeNotifier._internal();

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setDarkMode(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}

/// Reactive notifier for global text scaling.
/// Wraps AccessibilitySettings.getFontScale() so the entire app
/// rebuilds when the user changes text size in Settings.
class TextScaleNotifier extends ChangeNotifier {
  static final TextScaleNotifier _instance = TextScaleNotifier._internal();
  factory TextScaleNotifier() => _instance;
  TextScaleNotifier._internal();

  double _scale = 1.0;
  double get scale => _scale;

  Future<void> initialize() async {
    _scale = await AccessibilitySettings.getFontScale();
    notifyListeners();
  }

  Future<void> setScale(double value) async {
    _scale = value.clamp(0.8, 2.0);
    notifyListeners();
    await AccessibilitySettings.setFontScale(_scale);
  }
}

class VisualAssistantApp extends StatefulWidget {
  const VisualAssistantApp({super.key});

  @override
  State<VisualAssistantApp> createState() => _VisualAssistantAppState();
}

class _VisualAssistantAppState extends State<VisualAssistantApp> {
  final ThemeNotifier _themeNotifier = ThemeNotifier();
  final LanguageNotifier _langNotifier = LanguageNotifier();
  final TextScaleNotifier _textScaleNotifier = TextScaleNotifier();

  /// Check if user has a completed profile in Firestore
  static Future<bool> _checkUserProfileExists(User user) async {
    try {
      final displayName = user.displayName;
      if (displayName == null || displayName.isEmpty) return false;
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(displayName)
              .get();
      if (!doc.exists) return false;
      final profile = doc.data()?['profile'] as Map<String, dynamic>?;
      // Check that essential fields exist (phone + emergency contact)
      return profile != null &&
          profile['phone'] != null &&
          (profile['phone'] as String).isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ Error checking user profile: $e');
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _themeNotifier.addListener(_rebuild);
    _langNotifier.addListener(_rebuild);
    _textScaleNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    _themeNotifier.removeListener(_rebuild);
    _langNotifier.removeListener(_rebuild);
    _textScaleNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppThemeConfig.lightTheme,
      darkTheme: AppThemeConfig.darkTheme,
      themeMode: _themeNotifier.themeMode,
      // Apply global text scaling from Settings
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(_textScaleNotifier.scale)),
          child: child!,
        );
      },
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            return Scaffold(
              body: Center(child: Text("Error: ${snapshot.error}")),
            );
          } else if (snapshot.hasData) {
            final user = snapshot.data!;
            final isEmailProvider = user.providerData.any(
              (p) => p.providerId == 'password',
            );
            if (isEmailProvider && !user.emailVerified) {
              return const LoginScreen();
            }
            // For Google users, check if profile exists in Firestore
            final isGoogleProvider = user.providerData.any(
              (p) => p.providerId == 'google.com',
            );
            if (isGoogleProvider) {
              return FutureBuilder<bool>(
                future: _checkUserProfileExists(user),
                builder: (context, profileSnapshot) {
                  if (profileSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final hasProfile = profileSnapshot.data ?? false;
                  if (!hasProfile) {
                    // New Google user — send to registration completion
                    return LoginScreen(isNewGoogleUser: true, googleUser: user);
                  }
                  return const SafetyMonitor(child: HomeScreen());
                },
              );
            }
            return const SafetyMonitor(child: HomeScreen());
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }
}

/// Home Screen — 九宫格 (Big Grid) accessible menu.
/// Rebuilt with WCAG-standard large tiles, Semantics labels, and localization.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LanguageNotifier _langNotifier = LanguageNotifier();
  final TTSService _ttsService = TTSService();
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _langNotifier.addListener(_refresh);
    _initTts();
  }

  Future<void> _initTts() async {
    await _ttsService.initialize();
    final strings = AppLocalizations(_langNotifier.languageCode);
    await _ttsService.speak(strings.get('welcome'));
  }

  @override
  void dispose() {
    _langNotifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations(_langNotifier.languageCode);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('appTitle')),
        centerTitle: true,
        actions: [],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Scrollable Welcome text & List Menu
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Welcome text
                      const SizedBox(height: 8),
                      Semantics(
                        header: true,
                        child: Text(
                          strings.get('welcome'),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        strings.get('chooseFeature'),
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // —— USER PROFILE ——
                      _buildFeatureButton(
                        icon: Icons.person_outline,
                        label: strings.get('profileTitle'),
                        subtitle: 'Update your details',
                        semanticLabel: '${strings.get('profileTitle')} button',
                        onTap: () async {
                          await _ttsService.speak(
                            strings.get('openingProfile'),
                          );
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // —— OBJECT DETECTION ——
                      _buildFeatureButton(
                        icon: Icons.remove_red_eye_rounded,
                        label: strings.get('objectDetection'),
                        subtitle: strings.get('objectDetectionSubtitle'),
                        semanticLabel: strings.get('objectDetectionSemantic'),
                        onTap: () async {
                          await _ttsService.speak(
                            strings.get('openingObjectDetection'),
                          );
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ObjectDetectionScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // —— LIVE ASSISTANT ——
                      _buildFeatureButton(
                        icon: Icons.videocam_rounded,
                        label: strings.get('liveAssistant'),
                        subtitle: strings.get('liveAssistantSubtitle'),
                        semanticLabel: strings.get('liveAssistantSemantic'),
                        onTap: () async {
                          await _ttsService.speak(
                            strings.get('openingLiveAssistant'),
                          );
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LiveScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),


                      // —— NAVIGATION ——
                      _buildFeatureButton(
                        icon: Icons.navigation_rounded,
                        label: strings.get('navigate'),
                        subtitle: strings.get('navigateSubtitle'),
                        semanticLabel: strings.get('navigateSemantic'),
                        onTap: () async {
                          await _ttsService.speak(
                            strings.get('openingNavigation'),
                          );
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NavigationScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // —— CHATBOT ——
                      _buildFeatureButton(
                        icon: Icons.chat,
                        label: strings.get('chatbot'),
                        subtitle: 'AI assistant',
                        semanticLabel: '${strings.get('chatbot')} button',
                        onTap: () async {
                          await _ttsService.speak(
                            strings.get('openingChatbot'),
                          );
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChatScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // —— VISION AWARENESS ——
                      _buildFeatureButton(
                        icon: Icons.visibility_off_outlined,
                        label: strings.get('visionAwareness'),
                        subtitle: 'Educational simulations',
                        semanticLabel:
                            '${strings.get('visionAwareness')} button',
                        onTap: () async {
                          await _ttsService.speak(
                            strings.get('openingVisionAwareness'),
                          );
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AwarenessMenuScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // —— SETTINGS ——
                      _buildFeatureButton(
                        icon: Icons.settings,
                        label: strings.get('settings'),
                        subtitle: 'Accessibility & preferences',
                        semanticLabel: '${strings.get('settings')} button',
                        onTap: () async {
                          await _ttsService.speak(
                            strings.get('openingSettings'),
                          );
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
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
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () {
          if (_isNavigating) return;
          _isNavigating = true;
          onTap();
          // Reset after a delay to allow the page transition to complete
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) _isNavigating = false;
          });
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white,
              width: 2,
            ), // High contrast border
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.1),
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
                  color: Colors.white.withOpacity(0.9), // Enhanced readability
                  fontSize: 16,
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

// ---------------------------------------------------------------------------
// SAFETY MONITOR (Background Fall Detection)
// ---------------------------------------------------------------------------

class SafetyMonitor extends StatefulWidget {
  final Widget child;
  const SafetyMonitor({super.key, required this.child});

  @override
  State<SafetyMonitor> createState() => _SafetyMonitorState();
}

class _SafetyMonitorState extends State<SafetyMonitor> {
  StreamSubscription? _accelerometerSubscription;
  late AudioPlayer _audioPlayer;

  bool _isFreeFalling = false;
  DateTime? _freeFallTimestamp;
  bool _isAlertActive = false;
  String _emergencyPhone = '';

  final double _freeFallThreshold = 1.5;
  final double _impactThreshold = 20.0;
  final int _timeWindowMs = 500;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _loadEmergencyContact();
    _initFallDetection();
  }

  Future<void> _loadEmergencyContact() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      if (doc.exists) {
        final profile = doc.data()?['profile'] as Map<String, dynamic>?;
        if (profile != null && profile['emergencyContactPhone'] != null) {
          _emergencyPhone = profile['emergencyContactPhone'] as String;
          debugPrint('📞 Emergency contact loaded: $_emergencyPhone');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load emergency contact: $e');
    }
  }

  void _initFallDetection() {
    _accelerometerSubscription = accelerometerEvents.listen((
      AccelerometerEvent event,
    ) {
      if (_isAlertActive) return;

      double magnitude = (event.x.abs() + event.y.abs() + event.z.abs());

      if (magnitude < _freeFallThreshold) {
        _isFreeFalling = true;
        _freeFallTimestamp = DateTime.now();
      }

      if (_isFreeFalling && magnitude > _impactThreshold) {
        if (_freeFallTimestamp != null &&
            DateTime.now().difference(_freeFallTimestamp!).inMilliseconds <
                _timeWindowMs) {
          _triggerEmergencyProtocol();
        }
        _isFreeFalling = false;
      }
    });
  }

  Future<void> _triggerEmergencyProtocol() async {
    if (_isAlertActive) return;
    setState(() => _isAlertActive = true);

    try {
      await _audioPlayer.setAsset('assets/audio/siren.mp3');
      await _audioPlayer.setLoopMode(LoopMode.one);
      _audioPlayer.play();
    } catch (e) {
      debugPrint("Audio error: $e");
    }

    Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 1);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => EmergencyCountdownDialog(
            onCancel: () {
              _stopAlarm();
              setState(() => _isAlertActive = false);
              // Show feedback after cancel (false trigger)
              _showFallDetectionFeedback(callWasMade: false);
            },
            onTrigger: () {
              _stopAlarm();
              setState(() => _isAlertActive = false);
              if (_emergencyPhone.isNotEmpty) {
                _executeForceCall(_emergencyPhone);
              } else {
                debugPrint('⚠️ No emergency contact set');
              }
              // Show feedback after call trigger
              _showFallDetectionFeedback(callWasMade: true);
            },
          ),
    ).then((_) {
      if (_isAlertActive) {
        _stopAlarm();
        setState(() => _isAlertActive = false);
      }
    });
  }

  void _stopAlarm() {
    Vibration.cancel();
    _audioPlayer.stop();
  }

  Future<void> _executeForceCall(String phoneNumber) async {
    bool? res = await FlutterPhoneDirectCaller.callNumber(phoneNumber);
    if (res == false) {
      debugPrint("Failed to call");
    }
  }

  // ── Fall Detection Feedback Dialog ──

  void _showFallDetectionFeedback({required bool callWasMade}) {
    if (!mounted) return;
    // Delay slightly so the emergency dialog fully dismisses first
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      bool? triggerCorrect;
      bool? callCorrect;
      int step =
          1; // 1 = trigger question, 2 = call question (only if call was made)

      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (ctx) => StatefulBuilder(
              builder: (ctx, setDialogState) {
                if (step == 1) {
                  // Question 1: Was fall detection triggered correctly?
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: const Row(
                      children: [
                        Icon(
                          Icons.feedback_outlined,
                          color: Colors.amberAccent,
                          size: 28,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Fall Detection Feedback',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    content: const Text(
                      'Was the fall detection triggered correctly?',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                    actionsAlignment: MainAxisAlignment.spaceEvenly,
                    actions: [
                      TextButton(
                        onPressed: () {
                          triggerCorrect = false;
                          if (callWasMade) {
                            setDialogState(() => step = 2);
                          } else {
                            Navigator.pop(ctx);
                            _uploadFallFeedback(
                              triggerCorrect: false,
                              callCorrect: null,
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFE53935,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(
                                0xFFE53935,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Text(
                            'Incorrect',
                            style: TextStyle(
                              color: Color(0xFFEF5350),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          triggerCorrect = true;
                          if (callWasMade) {
                            setDialogState(() => step = 2);
                          } else {
                            Navigator.pop(ctx);
                            _uploadFallFeedback(
                              triggerCorrect: true,
                              callCorrect: null,
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Correct',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  // Question 2: Was the correct emergency number called?
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: const Row(
                      children: [
                        Icon(
                          Icons.phone_callback_outlined,
                          color: Colors.amberAccent,
                          size: 28,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Emergency Call Feedback',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    content: Text(
                      'Was the correct emergency number called?\n\nNumber dialed: $_emergencyPhone',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                    ),
                    actionsAlignment: MainAxisAlignment.spaceEvenly,
                    actions: [
                      TextButton(
                        onPressed: () {
                          callCorrect = false;
                          Navigator.pop(ctx);
                          _uploadFallFeedback(
                            triggerCorrect: triggerCorrect!,
                            callCorrect: false,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFE53935,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(
                                0xFFE53935,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Text(
                            'Incorrect',
                            style: TextStyle(
                              color: Color(0xFFEF5350),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          callCorrect = true;
                          Navigator.pop(ctx);
                          _uploadFallFeedback(
                            triggerCorrect: triggerCorrect!,
                            callCorrect: true,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Correct',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
      );
    });
  }

  Future<void> _uploadFallFeedback({
    required bool triggerCorrect,
    required bool? callCorrect,
  }) async {
    try {
      // Get user's phone number from Firestore profile
      String userPhone = '';
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.displayName != null) {
        final doc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.displayName)
                .get();
        if (doc.exists) {
          final profile = doc.data()?['profile'] as Map<String, dynamic>?;
          userPhone = profile?['phone'] as String? ?? '';
        }
      }

      await FirebaseFirestore.instance
          .collection('fall_detection_feedback')
          .add({
            'userPhone': userPhone,
            'triggerCorrect': triggerCorrect ? 'correct' : 'incorrect',
            'callCorrect':
                callCorrect != null
                    ? (callCorrect ? 'correct' : 'incorrect')
                    : 'not_applicable',
            'emergencyNumberDialed': _emergencyPhone,
            'timestamp': FieldValue.serverTimestamp(),
            'deviceTime': DateTime.now().toIso8601String(),
            'userId': user?.uid ?? '',
          });

      debugPrint('✅ Fall detection feedback uploaded');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks! Feedback recorded.'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Fall detection feedback upload failed: $e');
    }
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class EmergencyCountdownDialog extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onTrigger;
  const EmergencyCountdownDialog({
    super.key,
    required this.onCancel,
    required this.onTrigger,
  });

  @override
  State<EmergencyCountdownDialog> createState() =>
      _EmergencyCountdownDialogState();
}

class _EmergencyCountdownDialogState extends State<EmergencyCountdownDialog> {
  int _secondsRemaining = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 1) {
        timer.cancel();
        Navigator.pop(context);
        widget.onTrigger();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations(LanguageNotifier().languageCode);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 1),
            Text(
              strings.get('fallDetected'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              strings.get('callingAssistance'),
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              "$_secondsRemaining",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 80,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(flex: 1),
            Center(
              child: Semantics(
                label: strings.get('imOkayButton'),
                button: true,
                child: SizedBox(
                  width: 330,
                  height: 330,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 10,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onCancel();
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 60,
                          color: Colors.black,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          strings.get('imOkay'),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          strings.get('cancelAlarm'),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
