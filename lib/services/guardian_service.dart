import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class GuardianService {
  StreamSubscription? _accelSubscription;
  Function? onFallDetected;

  // LOGIC: A fall is Two Stages.
  // Stage 1: "Floating" (Free fall) - Gravity near 0.
  // Stage 2: "Impact" (Hitting bed/floor) - High Gravity.
  bool _isFloating = false;
  DateTime? _floatStartTime;

  // TUNING (Adjust these if needed)
  final double floatThreshold = 2.0; // Below 2.0 means falling/floating
  final double impactThreshold = 10.0; // Impact force (Bed is soft, so 10 is good)

  void startListening({required Function onFall}) {
    onFallDetected = onFall;
    _isFloating = false;

    // We use RAW Accelerometer (includes Gravity) to detect "Zero G"
    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      double gForce = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));

      // STAGE 1: DETECT THE DROP (Weightlessness)
      // If you swing the phone, G-Force goes UP (not down). 
      // Only a drop makes G-Force go DOWN near 0.
      if (gForce < floatThreshold) {
        if (!_isFloating) {
          _isFloating = true;
          _floatStartTime = DateTime.now();
          print("📉 STAGE 1: Free Fall Detected (Floating)");
        }
      }

      // STAGE 2: DETECT THE LANDING (Impact)
      // Must happen within 1 second of floating.
      if (_isFloating && gForce > impactThreshold) {
        final timeDiff = DateTime.now().difference(_floatStartTime!).inMilliseconds;
        
        // If impact happens 100ms to 1000ms after float -> REAL FALL
        if (timeDiff > 100 && timeDiff < 1000) {
          print("💥 STAGE 2: IMPACT CONFIRMED!");
          triggerFall();
        } else if (timeDiff > 1000) {
          // Took too long (maybe just put down gently)
          _isFloating = false; 
        }
      }
    });
  }

  void triggerFall() {
    if (onFallDetected != null) {
      onFallDetected!();
      _isFloating = false;
      stopListening(); 
    }
  }

  void stopListening() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
  }
}