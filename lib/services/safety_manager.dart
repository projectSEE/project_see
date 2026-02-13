import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart'; // NEW PLUGIN
import 'package:permission_handler/permission_handler.dart';
import '../screens/alert_screen.dart'; 
import 'guardian_service.dart';
import 'vision_service.dart';

class SafetyManager {
  final GuardianService _guardian = GuardianService();
  
  // UPDATE YOUR NUMBER HERE
  final String _emergencyNumber = "0123456789"; 

  BuildContext? context;
  bool _isAlertOpen = false;

  void startSystem(BuildContext ctx) {
    context = ctx;
    _checkPhonePermission();
    _startMonitoring();
    print("Safety Manager: Active (Anti-Swing Mode)");
  }

  void _startMonitoring() {
    _guardian.startListening(onFall: handleFall);
  }

  void stopSystem() {
    _guardian.stopListening();
  }

  Future<void> handleFall() async { 
    if (context != null && context!.mounted && !_isAlertOpen) {
      _isAlertOpen = true;
      _guardian.stopListening(); 
      
      await Navigator.push(
        context!,
        MaterialPageRoute(
          builder: (context) => AlertScreen(
            onEmergency: executeForceCall, // Uses the new Force Call
          ),
        ),
      );
      
      _isAlertOpen = false;
      _startMonitoring(); 
    }
  }

  void handleVisionResult(Map<String, dynamic> result) {
    if (result['danger'] == true) {
      handleFall();
    }
  }

  // --- THE FORCE CALLER (Bypasses "Complete Action Using") ---
  Future<void> executeForceCall() async {
    print("⚠️ TIMER ENDED: FORCING SYSTEM CALL... ⚠️");
    
    // We create a specific Android Intent that targets the Google Phone App directly.
    // This tells Android: "Don't ask Zoom. Don't ask Skype. Give this to the Phone."
    final intent = AndroidIntent(
      action: 'android.intent.action.CALL',
      data: 'tel:$_emergencyNumber',
      package: 'com.google.android.dialer', // Standard Redmi/Xiaomi Dialer
      // If the above doesn't work, try 'com.android.contacts' or 'com.android.phone'
    );
    
    try {
      await intent.launch();
    } catch (e) {
      print("Error launching intent: $e");
      // Fallback if they don't have Google Dialer (Rare)
      final fallbackIntent = AndroidIntent(
        action: 'android.intent.action.CALL',
        data: 'tel:$_emergencyNumber',
      );
      await fallbackIntent.launch();
    }
  }

  Future<void> _checkPhonePermission() async {
    var status = await Permission.phone.status;
    if (!status.isGranted) {
      await Permission.phone.request();
    }
  }
}