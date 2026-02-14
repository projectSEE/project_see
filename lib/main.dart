import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'screens/obstacle_detector_screen.dart';
import 'theme/theme.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const VisualAssistantApp());
}

/// Global theme notifier for immediate theme switching
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
      home: const HomeScreen(),
    );
  }
}

/// Simple home screen with two navigation buttons
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
