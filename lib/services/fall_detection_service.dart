import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

class FallDetectionService {
  StreamSubscription? _subscription;
  
  // Logic Thresholds
  final double _freeFallThreshold = 1.5;
  final double _impactThreshold = 20.0;
  final int _timeWindowMs = 500;

  bool _isFreeFalling = false;
  DateTime? _freeFallTimestamp;

  void startListening(Function onFallDetected) {
    _subscription = accelerometerEvents.listen((AccelerometerEvent event) {
      // Calculate magnitude
      double magnitude = (event.x.abs() + event.y.abs() + event.z.abs());

      // Stage A: Free Fall
      if (magnitude < _freeFallThreshold) {
        _isFreeFalling = true;
        _freeFallTimestamp = DateTime.now();
      }

      // Stage B: Impact
      if (_isFreeFalling && magnitude > _impactThreshold) {
        if (_freeFallTimestamp != null &&
            DateTime.now().difference(_freeFallTimestamp!).inMilliseconds < _timeWindowMs) {
          onFallDetected(); // Trigger the response phase
        }
        _isFreeFalling = false; 
      }
    });
  }

  void stopListening() {
    _subscription?.cancel();
  }
}