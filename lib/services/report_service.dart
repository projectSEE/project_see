import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class ReportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> reportHazard(String hazardType) async {
    try {
      // 1. Ask for GPS permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // 2. Get Current Location (Fixed Syntax)
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high)
      );

      // 3. Upload to Firestore
      await _db.collection('hazards').add({
        'type': hazardType, 
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'ACTIVE',
      });

      // ignore: avoid_print
      print("✅ Hazard uploaded to Firestore!");
      
    } catch (e) {
      // ignore: avoid_print
      print("❌ Error uploading hazard: $e");
    }
  }
}