import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NetworkService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> uploadHazard(Map<String, dynamic> visionResult) async {
    try {
      // We use the current timestamp as the ID
      String hazardId = DateTime.now().millisecondsSinceEpoch.toString();

      await _db.collection('hazards').doc(hazardId).set({
        'type': visionResult['reason'] ?? 'Unknown Hazard',
        'isDanger': visionResult['danger'] ?? true,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
        'status': 'reported',
      });

      print("Cloud: Hazard uploaded successfully!");
    } catch (e) {
      print("Cloud Error: $e");
    }
  }
}