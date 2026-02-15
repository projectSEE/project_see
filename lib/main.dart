import 'dart:async';
import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'screens/obstacle_detector_screen.dart';
import 'theme/theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:just_audio/just_audio.dart'; // Import for siren

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
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
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
      home: const SafetyMonitor(child: HomeScreen()),
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
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.visibility,
                size: 80,
                color: Colors.blueAccent,
              ),
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
                  label: const Text(
                    'Chatbot',
                    style: TextStyle(fontSize: 18),
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
  late AudioPlayer _audioPlayer; // Added AudioPlayer
  
  bool _isFreeFalling = false;
  DateTime? _freeFallTimestamp;
  bool _isAlertActive = false;

  final double _freeFallThreshold = 1.5;
  final double _impactThreshold = 20.0;
  final int _timeWindowMs = 500;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer(); // Initialize player
    _initFallDetection();
  }

  void _initFallDetection() {
    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      if (_isAlertActive) return;

      double magnitude = (event.x.abs() + event.y.abs() + event.z.abs());

      if (magnitude < _freeFallThreshold) {
        _isFreeFalling = true;
        _freeFallTimestamp = DateTime.now();
      }

      if (_isFreeFalling && magnitude > _impactThreshold) {
        if (_freeFallTimestamp != null &&
            DateTime.now().difference(_freeFallTimestamp!).inMilliseconds < _timeWindowMs) {
          _triggerEmergencyProtocol();
        }
        _isFreeFalling = false;
      }
    });
  }

  Future<void> _triggerEmergencyProtocol() async {
    if (_isAlertActive) return;
    setState(() => _isAlertActive = true);
    
    // 1. Play Siren on Loop
    try {
      await _audioPlayer.setAsset('assets/audio/siren.mp3');
      await _audioPlayer.setLoopMode(LoopMode.one); // Loop forever
      _audioPlayer.play();
    } catch (e) {
      debugPrint("Audio error: $e");
    }

    // 2. Vibrate
    Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 1);

    // 3. Show Big Button Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmergencyCountdownDialog(
        onCancel: () {
          _stopAlarm();
          setState(() => _isAlertActive = false);
        },
        onTrigger: () {
          _stopAlarm();
          // Pass the phone number here (Change this to your emergency number)
          _executeForceCall("+60123456789"); 
        },
      ),
    ).then((_) {
       // Just in case dialog is closed via back button (though barrierDismissible prevents it)
       if (_isAlertActive) {
         _stopAlarm();
         setState(() => _isAlertActive = false);
       }
    });
  }

  void _stopAlarm() {
    Vibration.cancel();
    _audioPlayer.stop(); // Stop the siren
  }

  Future<void> _executeForceCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
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
  const EmergencyCountdownDialog({super.key, required this.onCancel, required this.onTrigger});

  @override
  State<EmergencyCountdownDialog> createState() => _EmergencyCountdownDialogState();
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
        Navigator.pop(context); // Close dialog
        widget.onTrigger(); // Call logic
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
    // Using a full screen overlay look with a big central button
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
                fontWeight: FontWeight.bold
              ), 
              textAlign: TextAlign.center
            ),
            const SizedBox(height: 10),
            const Text(
              "Calling assistance in:", 
              style: TextStyle(color: Colors.white70, fontSize: 18)
            ),
            const SizedBox(height: 10),
            Text(
              "$_secondsRemaining", 
              style: const TextStyle(
                color: Colors.white, 
                fontSize: 80, 
                fontWeight: FontWeight.bold
              )
            ),
            const Spacer(flex: 1),
            
            // THE BIG CIRCLE BUTTON
            Center(
              child: SizedBox(
                width: 250, // Massive width
                height: 250, // Massive height
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.shade400, // High contrast green for safety
                    shape: const CircleBorder(), // Makes it a perfect circle
                    elevation: 10,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onCancel();
                  },
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 60, color: Colors.black87),
                      SizedBox(height: 10),
                      Text(
                        "I'M OKAY",
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 28, 
                          fontWeight: FontWeight.bold
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