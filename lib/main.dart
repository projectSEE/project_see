import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Uses google-services.json on Android
  runApp(const VisualAssistantApp());
}

class VisualAssistantApp extends StatelessWidget {
  const VisualAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Assistant',
      debugShowCheckedModeBanner: false,
      // High Contrast Theme
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.yellowAccent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.yellowAccent,
          secondary: Colors.cyanAccent,
          surface: Color(0xFF1E1E1E),
          onPrimary: Colors.black,
          onSurface: Colors.white,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 24, color: Colors.white, height: 1.5),
          bodyMedium: TextStyle(fontSize: 20, color: Colors.white, height: 1.5),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.yellowAccent,
          titleTextStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}
