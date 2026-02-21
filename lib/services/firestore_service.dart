import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Service for Firestore database and Firebase Storage operations.
/// 
/// Structure:
/// - conversations/{userId}/topics/{topicId}/messages/{messageId}
/// - users/{userId}
/// - pois/{poiId}
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ==================== Image Storage ====================

  /// Upload image to Firebase Storage and return download URL.
  Future<String?> uploadImage(
    String userId,
    String topicId,
    Uint8List imageBytes,
  ) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref('chat_images/$userId/$topicId/$timestamp.jpg');
      
      await ref.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      
      return await ref.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  // ==================== Messages ====================

  /// Save a message to a conversation topic.
  Future<void> saveMessage(
    String userId,
    String role,
    String content, {
    bool hasImage = false,
    String? topicId,
    Uint8List? imageBytes,
  }) async {
    final actualTopicId = topicId ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    try {
      // Upload image if bytes provided
      String? imageUrl;
      if (imageBytes != null) {
        imageUrl = await uploadImage(userId, actualTopicId, imageBytes);
      }

      // Get reference to messages subcollection
      final messagesRef = _db
          .collection('conversations')
          .doc(userId)
          .collection('topics')
          .doc(actualTopicId)
          .collection('messages');

      // Add message
      await messagesRef.add({
        'role': role,
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
        'imageUrl': imageUrl,
        'hasImage': hasImage || imageBytes != null,
      });

      // Update topic metadata
      await _updateTopicMetadata(userId, actualTopicId, content, role);
    } catch (e) {
      print('Error saving message: $e');
    }
  }

  /// Update topic document with latest info.
  Future<void> _updateTopicMetadata(
    String userId,
    String topicId,
    String content,
    String role,
  ) async {
    final topicRef = _db
        .collection('conversations')
        .doc(userId)
        .collection('topics')
        .doc(topicId);

    final doc = await topicRef.get();
    
    if (doc.exists) {
      // Update existing topic
      await topicRef.update({
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastMessage': content.length > 100 ? '${content.substring(0, 100)}...' : content,
      });
    } else {
      // Create new topic
      await topicRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'firstMessage': content.length > 100 ? '${content.substring(0, 100)}...' : content,
        'lastMessage': content,
      });
    }
  }

  /// Get messages for a specific topic.
  Future<List<Map<String, dynamic>>> getMessages(
    String userId,
    String topicId,
  ) async {
    try {
      final snapshot = await _db
          .collection('conversations')
          .doc(userId)
          .collection('topics')
          .doc(topicId)
          .collection('messages')
          .orderBy('timestamp')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'role': data['role'] ?? 'unknown',
          'content': data['content'] ?? '',
          'timestamp': data['timestamp'],
          'imageUrl': data['imageUrl'],
        };
      }).toList();
    } catch (e) {
      print('Error getting messages: $e');
      return [];
    }
  }

  /// Get topic previews for chat history display.
  Future<List<Map<String, dynamic>>> getTopicPreviews(String userId) async {
    try {
      final snapshot = await _db
          .collection('conversations')
          .doc(userId)
          .collection('topics')
          .orderBy('lastUpdated', descending: true)
          .limit(50)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'topicId': doc.id,
          'firstMessage': data['firstMessage'] ?? '',
          'lastMessage': data['lastMessage'] ?? '',
          'createdAt': data['createdAt'],
          'lastUpdated': data['lastUpdated'],
        };
      }).toList();
    } catch (e) {
      print('Error getting topic previews: $e');
      return [];
    }
  }

  /// Get all conversations grouped by topic ID.
  Future<Map<String, List<Map<String, dynamic>>>> getConversationsGroupedByTopic(
    String userId,
  ) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    
    try {
      final topicsSnapshot = await _db
          .collection('conversations')
          .doc(userId)
          .collection('topics')
          .get();

      for (final topicDoc in topicsSnapshot.docs) {
        final topicId = topicDoc.id;
        final messages = await getMessages(userId, topicId);
        if (messages.isNotEmpty) {
          grouped[topicId] = messages;
        }
      }
    } catch (e) {
      print('Error getting grouped conversations: $e');
    }
    
    return grouped;
  }

  /// Delete old topics (older than 5 days).
  Future<void> cleanupOldConversations(String userId) async {
    try {
      final fiveDaysAgo = DateTime.now().subtract(const Duration(days: 5));
      
      final snapshot = await _db
          .collection('conversations')
          .doc(userId)
          .collection('topics')
          .where('lastUpdated', isLessThan: Timestamp.fromDate(fiveDaysAgo))
          .get();

      final batch = _db.batch();
      
      for (final doc in snapshot.docs) {
        // Delete all messages in topic
        final messages = await doc.reference.collection('messages').get();
        for (final msg in messages.docs) {
          batch.delete(msg.reference);
        }
        // Delete topic
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('Cleaned up ${snapshot.docs.length} old topics');
    } catch (e) {
      print('Error cleaning up conversations: $e');
    }
  }

  // ==================== User Settings ====================

  /// Get user accessibility settings.
  Future<Map<String, dynamic>> getAccessibilitySettings(String fullName) async {
    try {
      final doc = await _db.collection('users').doc(fullName).get();
      
      if (doc.exists && doc.data()?['settings'] != null) {
        return Map<String, dynamic>.from(doc.data()!['settings']);
      }
    } catch (e) {
      print('Error getting settings: $e');
    }
    
    // Return defaults
    return {
      'visualImpairment': false,
      'hearingImpairment': false,
      'mobilityImpairment': false,
      'preferredVoice': 'Kore',
      'speechRate': 1.0,
      'highContrastMode': true,
    };
  }

  /// Update user accessibility settings.
  Future<void> updateAccessibilitySettings(
    String fullName,
    Map<String, dynamic> settings,
  ) async {
    await _db.collection('users').doc(fullName).set({
      'settings': settings,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Update user profile.
  /// Document ID is the user's full name: users/{fullName}/profile
  Future<void> updateUserProfile(
    String fullName,
    Map<String, dynamic> data,
  ) async {
    data['lastActive'] = FieldValue.serverTimestamp();
    await _db.collection('users').doc(fullName).set(
      {'profile': data},
      SetOptions(merge: true),
    );
  }

  // ==================== POIs ====================

  /// Get all POIs.
  Future<List<Map<String, dynamic>>> getAllPOIs() async {
    try {
      final snapshot = await _db.collection('pois').get();
      
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error getting POIs: $e');
      return [];
    }
  }

  /// Get POIs by type.
  Future<List<Map<String, dynamic>>> getPOIsByType(String type) async {
    try {
      final snapshot = await _db
          .collection('pois')
          .where('type', isEqualTo: type)
          .get();
      
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error getting POIs by type: $e');
      return [];
    }
  }

  // ==================== AI Context ====================

  /// Build context for AI including user settings and recent messages.
  Future<Map<String, dynamic>> buildContextForAI(
    String fullName, {
    double? latitude,
    double? longitude,
  }) async {
    final context = <String, dynamic>{};

    try {
      context['accessibilitySettings'] = await getAccessibilitySettings(fullName);

      // Get nearby POIs if location provided
      if (latitude != null && longitude != null) {
        final allPOIs = await getAllPOIs();
        final nearbyPOIs = allPOIs.where((poi) {
          final coords = poi['coords'] as Map<String, dynamic>?;
          if (coords == null) return false;
          
          final lat = coords['latitude'] as num?;
          final lng = coords['longitude'] as num?;
          if (lat == null || lng == null) return false;
          
          // ~1km radius check
          return (lat - latitude).abs() < 0.01 && (lng - longitude).abs() < 0.01;
        }).toList();

        if (nearbyPOIs.isNotEmpty) {
          context['nearbyPOIs'] = nearbyPOIs;
        }
      }
    } catch (e) {
      print('Error building AI context: $e');
    }

    return context;
  }
}
