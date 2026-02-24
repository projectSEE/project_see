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
import 'package:just_audio/just_audio.dart';
import 'screens/awareness_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'core/localization/app_localizations.dart';
import 'core/services/language_provider.dart';
import 'utils/accessibility_settings.dart';

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

  @override
  void initState() {
    super.initState();
    _langNotifier.addListener(_refresh);
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

    // Menu items — each maps to a development screen
    final List<Map<String, dynamic>> menuItems = [
      {
        'icon': Icons.camera_alt,
        'label': strings.get('obstacleDetection'),
        'color': theme.colorScheme.primary,
        'screen': const ObstacleDetectorScreen(),
      },
      {
        'icon': Icons.chat,
        'label': strings.get('chatbot'),
        'color': theme.colorScheme.primary,
        'screen': const ChatScreen(),
      },
      {
        'icon': Icons.visibility_off_outlined,
        'label': strings.get('visionAwareness'),
        'color': Colors.purple,
        'screen': const AwarenessMenuScreen(),
      },
      {
        'icon': Icons.settings,
        'label': strings.get('settings'),
        'color': theme.colorScheme.secondary,
        'screen': const SettingsScreen(),
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('appTitle')),
        centerTitle: true,
        actions: [
          Semantics(
            label: strings.get('signOut'),
            button: true,
            child: IconButton(
              icon: const Icon(Icons.logout, size: 28),
              tooltip: strings.get('signOut'),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Welcome text
              const SizedBox(height: 8),
              Text(
                strings.get('welcome'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                strings.get('chooseFeature'),
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 九宫格 Grid
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Adjust aspect ratio based on text scale factor to prevent vertical overflow
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final crossAxisCount = 2;
                    final spacing = 16.0;
                    final itemWidth =
                        (constraints.maxWidth -
                            spacing * (crossAxisCount - 1)) /
                        crossAxisCount;
                    // Base item height without scaling is roughly equal to itemWidth, plus extra space for large text.
                    final itemHeight =
                        itemWidth +
                        (30 * textScale); // Add extra height for text
                    final childAspectRatio = itemWidth / itemHeight;

                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemCount: menuItems.length,
                      itemBuilder: (context, index) {
                        final item = menuItems[index];
                        return _buildMenuTile(
                          context,
                          icon: item['icon'],
                          label: item['label'],
                          color: item['color'],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => item['screen'] as Widget,
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a large, accessible grid tile with icon, label, and Semantics.
  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: color.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: color, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: color),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
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

  final double _freeFallThreshold = 1.5;
  final double _impactThreshold = 20.0;
  final int _timeWindowMs = 500;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initFallDetection();
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
            },
            onTrigger: () {
              _stopAlarm();
              // --- UPDATED CALL LOGIC ---
              _executeForceCall("+60175727549");
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

  // --- THIS IS THE FIXED FUNCTION ---
  Future<void> _executeForceCall(String phoneNumber) async {
    // FlutterPhoneDirectCaller automatically calls the number
    // It requires the 'android.permission.CALL_PHONE' in AndroidManifest.xml
    bool? res = await FlutterPhoneDirectCaller.callNumber(phoneNumber);
    if (res == false) {
      debugPrint("Failed to call");
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
      backgroundColor: Colors.red.shade900,
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
                      backgroundColor: Colors.greenAccent.shade400,
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
                          color: Colors.black87,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          strings.get('imOkay'),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          strings.get('cancelAlarm'),
                          style: const TextStyle(
                            color: Colors.black54,
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
