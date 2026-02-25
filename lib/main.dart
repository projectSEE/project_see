import 'dart:async';
import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'screens/obstacle_detector_screen.dart';
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
import 'screens/login_screen.dart'; // <--- NEW IMPORT


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

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

class VisualAssistantApp extends StatefulWidget {
  const VisualAssistantApp({super.key});

  @override
  State<VisualAssistantApp> createState() => _VisualAssistantAppState();
}

class _VisualAssistantAppState extends State<VisualAssistantApp> {
  final ThemeNotifier _themeNotifier = ThemeNotifier();

  @override
  void initState() {
    super.initState();
    _themeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppThemeConfig.lightTheme,
      darkTheme: AppThemeConfig.darkTheme,
      themeMode: _themeNotifier.themeMode,
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
            // For email/password users, require email verification
            final isEmailProvider = user.providerData
                .any((p) => p.providerId == 'password');
            if (isEmailProvider && !user.emailVerified) {
              // Not verified — show LoginScreen (don't sign out!)
              // The user stays signed in so LoginScreen can reload() them
              return const LoginScreen();
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual Assistant'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.visibility, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 16),
              const Text(
                'Welcome to Visual Assistant',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a feature to get started',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ObstacleDetectorScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.camera_alt, size: 28),
                  label: const Text(
                    'Obstacle Detection',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ChatScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat, size: 28),
                  label: const Text('Chatbot', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AwarenessMenuScreen(),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.visibility_off_outlined,
                    size: 28,
                  ), 
                  label: const Text(
                    'Vision Awareness',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.purple.shade100, 
                    foregroundColor: Colors.purple.shade900,
                  ),
                ),
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
      if (user == null || user.displayName == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.displayName)
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
      int step = 1; // 1 = trigger question, 2 = call question (only if call was made)

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (step == 1) {
              // Question 1: Was fall detection triggered correctly?
              return AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(
                  children: [
                    Icon(Icons.feedback_outlined, color: Colors.amberAccent, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Fall Detection Feedback',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
                      ),
                      child: const Text('Incorrect', style: TextStyle(color: Color(0xFFEF5350), fontSize: 16, fontWeight: FontWeight.w700)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Correct', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              );
            } else {
              // Question 2: Was the correct emergency number called?
              return AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(
                  children: [
                    Icon(Icons.phone_callback_outlined, color: Colors.amberAccent, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Emergency Call Feedback',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'Was the correct emergency number called?\n\nNumber dialed: $_emergencyPhone',
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
                      ),
                      child: const Text('Incorrect', style: TextStyle(color: Color(0xFFEF5350), fontSize: 16, fontWeight: FontWeight.w700)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Correct', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
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
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.displayName)
            .get();
        if (doc.exists) {
          final profile = doc.data()?['profile'] as Map<String, dynamic>?;
          userPhone = profile?['phone'] as String? ?? '';
        }
      }

      await FirebaseFirestore.instance.collection('fall_detection_feedback').add({
        'userPhone': userPhone,
        'triggerCorrect': triggerCorrect ? 'correct' : 'incorrect',
        'callCorrect': callCorrect != null
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
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 1),
            const Text(
              "FALL DETECTED!",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              "Calling assistance in:",
              style: TextStyle(color: Colors.white70, fontSize: 18),
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
              child: SizedBox(
                width: 330, 
                height: 330, 
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors
                            .greenAccent
                            .shade400, 
                    shape: const CircleBorder(), 
                    elevation: 10,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onCancel();
                  },
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 60,
                        color: Colors.black87,
                      ),
                      SizedBox(height: 10),
                      Text(
                        "I'M OKAY",
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "(Cancel Alarm)",
                        style: TextStyle(color: Colors.black54, fontSize: 16),
                      ),
                    ],
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