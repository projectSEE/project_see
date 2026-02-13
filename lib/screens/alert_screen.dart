import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Haptic Feedback
import '../services/audio_service.dart';

class AlertScreen extends StatefulWidget {
  final VoidCallback? onEmergency; 

  const AlertScreen({super.key, this.onEmergency});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final AudioService _audio = AudioService(); 
  int _countdown = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _audio.playSiren(); 
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_countdown > 0) {
            _countdown--;
          } else {
            _timer?.cancel();
            _triggerEmergency();
          }
        });
      }
    });
  }

  void _triggerEmergency() {
    if (widget.onEmergency != null) {
      widget.onEmergency!();
    }
  }

  void _cancelAlarm() {
    HapticFeedback.heavyImpact(); // Physical feedback
    _timer?.cancel();
    _audio.stopSiren(); 
    Navigator.pop(context); // Go back to Home
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audio.stopSiren(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: SafeArea(
        child: Column(
          children: [
            // Top Section: Small Countdown (Informational only)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(
                "Calling in $_countdown seconds...",
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
            ),
            
            // Middle Section: THE MASSIVE BUTTON
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 300, // HUGE width
                  height: 300, // HUGE height
                  child: ElevatedButton(
                    onPressed: _cancelAlarm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red,
                      shape: const CircleBorder(), // Makes it a perfect circle
                      elevation: 20, // 3D effect so it feels "pressable"
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.stop_circle_outlined, size: 80, color: Colors.red),
                        SizedBox(height: 10),
                        Text(
                          "I AM OKAY",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 35, // Very large text
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "(Tap to Stop)",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // Bottom Section: Status
            const Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Text(
                "FALL DETECTED",
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: 28, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}