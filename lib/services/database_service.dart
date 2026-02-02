import 'package:firebase_database/firebase_database.dart';

/// Service for managing Firebase Realtime Database operations.
/// Handles user profiles, accessibility settings, conversation history, and POIs.
class DatabaseService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  // ==================== Helper Methods ====================
  
  /// Safely convert Firebase snapshot value to Map<String, dynamic>.
  /// Handles various Firebase return types including Maps and Lists.
  Map<String, dynamic>? _toMap(Object? value) {
    if (value == null) return null;
    
    // Already a Map - convert it
    if (value is Map) {
      try {
        return Map<String, dynamic>.from(value);
      } catch (e) {
        print('Error converting Map: $e, value type: ${value.runtimeType}');
        return null;
      }
    }
    
    // Firebase sometimes returns Lists when keys are sequential integers
    if (value is List) {
      final map = <String, dynamic>{};
      for (var i = 0; i < value.length; i++) {
        if (value[i] != null) {
          map[i.toString()] = value[i];
        }
      }
      return map.isEmpty ? null : map;
    }
    
    // Not a Map or List - cannot convert
    print('Cannot convert to Map: ${value.runtimeType}');
    return null;
  }
  
  /// Safely convert value to a conversation entry.
  /// Manually extracts fields to avoid type casting issues.
  Map<String, dynamic>? _toConversation(Object? value, String key) {
    if (value == null) return null;
    
    // Only process if it's a Map-like object
    if (value is! Map) {
      print('Conversation entry is not a Map: ${value.runtimeType} = $value');
      return null;
    }
    
    // Manually extract each field to avoid Map.from() issues
    try {
      final conv = <String, dynamic>{
        'id': key,
        'role': value['role']?.toString() ?? 'unknown',
        'content': value['content']?.toString() ?? '',
        'timestamp': value['timestamp'] is num ? value['timestamp'] : 0,
        'hasImage': value['hasImage'] == true,
      };
      return conv;
    } catch (e) {
      print('Error extracting conversation fields: $e');
      return null;
    }
  }
  
  // ==================== User Profile ====================
  
  /// Get user profile data.
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final snapshot = await _database.ref('users/$userId/profile').get();
      if (snapshot.exists) {
        return _toMap(snapshot.value);
      }
    } catch (e) {
      print('Error getting user profile: $e');
    }
    return null;
  }
  
  /// Update user profile data.
  Future<void> updateUserProfile(String userId, Map<String, dynamic> data) async {
    data['lastActive'] = ServerValue.timestamp;
    await _database.ref('users/$userId/profile').update(data);
  }
  
  // ==================== Accessibility Settings ====================
  
  /// Get user accessibility settings.
  Future<Map<String, dynamic>> getAccessibilitySettings(String userId) async {
    try {
      final snapshot = await _database.ref('users/$userId/accessibilitySettings').get();
      if (snapshot.exists) {
        final data = _toMap(snapshot.value);
        if (data != null) return data;
      }
    } catch (e) {
      print('Error getting accessibility settings: $e');
    }
    // Return defaults if not set or error
    return {
      'visualImpairment': false,
      'hearingImpairment': false,
      'mobilityImpairment': false,
      'preferredVoice': 'Kore',
      'speechRate': 1.0,
      'highContrastMode': true,
    };
  }
  
  /// Update accessibility settings.
  Future<void> updateAccessibilitySettings(String userId, Map<String, dynamic> settings) async {
    await _database.ref('users/$userId/accessibilitySettings').update(settings);
  }
  
  /// Listen to accessibility settings changes.
  Stream<DatabaseEvent> listenToAccessibilitySettings(String userId) {
    return _database.ref('users/$userId/accessibilitySettings').onValue;
  }
  
  // ==================== Conversation History ====================
  
  /// Get recent conversations (within last 3 days).
  /// Completely defensive - handles any data format from Firebase.
  Future<List<Map<String, dynamic>>> getRecentConversations(String userId) async {
    try {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      
      final snapshot = await _database
          .ref('users/$userId/conversations')
          .orderByChild('timestamp')
          .startAt(threeDaysAgo)
          .get();
      
      if (!snapshot.exists) {
        print('No conversations found for user $userId');
        return [];
      }
      
      final rawValue = snapshot.value;
      print('DEBUG: Conversations raw type: ${rawValue.runtimeType}');
      print('DEBUG: Conversations raw value preview: ${rawValue.toString().substring(0, rawValue.toString().length > 200 ? 200 : rawValue.toString().length)}');
      
      final conversations = <Map<String, dynamic>>[];
      
      // Handle Map format (normal Firebase response)
      if (rawValue is Map) {
        for (final entry in rawValue.entries) {
          try {
            final key = entry.key.toString();
            final value = entry.value;
            print('DEBUG: Processing key=$key, valueType=${value.runtimeType}');
            
            if (value is Map) {
              final conv = _toConversation(value, key);
              if (conv != null) {
                conversations.add(conv);
              }
            } else {
              print('DEBUG: Skipping non-Map value at key $key: ${value.runtimeType}');
            }
          } catch (e) {
            print('DEBUG: Error processing conversation entry: $e');
          }
        }
      }
      // Handle List format (when keys are sequential integers)
      else if (rawValue is List) {
        for (var i = 0; i < rawValue.length; i++) {
          try {
            final value = rawValue[i];
            if (value != null && value is Map) {
              final conv = _toConversation(value, i.toString());
              if (conv != null) {
                conversations.add(conv);
              }
            }
          } catch (e) {
            print('DEBUG: Error processing list entry $i: $e');
          }
        }
      }
      // Handle String or other types - this is malformed data
      else if (rawValue is String) {
        print('DEBUG: Conversations node contains a raw string, not objects. Returning empty.');
        return [];
      }
      else {
        print('DEBUG: Unknown data type: ${rawValue.runtimeType}');
        return [];
      }
      
      // Sort by timestamp ascending
      conversations.sort((a, b) {
        final aTime = a['timestamp'];
        final bTime = b['timestamp'];
        if (aTime is num && bTime is num) {
          return aTime.compareTo(bTime);
        }
        return 0;
      });
      
      print('DEBUG: Returning ${conversations.length} conversations');
      return conversations;
    } catch (e, stackTrace) {
      print('Error getting conversations: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }
  
  /// Save a new message to conversation history.
  Future<void> saveMessage(String userId, String role, String content, {bool hasImage = false}) async {
    try {
      final ref = _database.ref('users/$userId/conversations').push();
      await ref.set({
        'role': role,
        'content': content,
        'timestamp': ServerValue.timestamp,
        'hasImage': hasImage,
      });
    } catch (e) {
      print('Error saving message: $e');
    }
  }
  
  /// Cleanup old conversations (older than 3 days).
  /// Completely defensive - handles any data format from Firebase.
  Future<void> cleanupOldConversations(String userId) async {
    try {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      
      final snapshot = await _database
          .ref('users/$userId/conversations')
          .orderByChild('timestamp')
          .endAt(threeDaysAgo)
          .get();
      
      if (!snapshot.exists) {
        print('DEBUG: No old conversations to cleanup for user $userId');
        return;
      }
      
      final rawValue = snapshot.value;
      print('DEBUG: Cleanup raw type: ${rawValue.runtimeType}');
      
      // If raw value is a String or not a collection, there's malformed data
      if (rawValue is! Map && rawValue is! List) {
        print('DEBUG: Cleanup found non-collection data type: ${rawValue.runtimeType}. Skipping cleanup.');
        return;
      }
      
      final updates = <String, dynamic>{};
      
      // Handle Map format
      if (rawValue is Map) {
        for (final entry in rawValue.entries) {
          try {
            final key = entry.key.toString();
            // Only delete if the value is a valid conversation object
            if (entry.value is Map) {
              updates['users/$userId/conversations/$key'] = null;
            }
          } catch (e) {
            print('DEBUG: Error processing cleanup key: $e');
          }
        }
      }
      // Handle List format
      else if (rawValue is List) {
        for (var i = 0; i < rawValue.length; i++) {
          try {
            if (rawValue[i] != null && rawValue[i] is Map) {
              updates['users/$userId/conversations/$i'] = null;
            }
          } catch (e) {
            print('DEBUG: Error processing cleanup index $i: $e');
          }
        }
      }
      
      if (updates.isNotEmpty) {
        await _database.ref().update(updates);
        print('DEBUG: Cleaned up ${updates.length} old conversations');
      } else {
        print('DEBUG: No valid conversations to cleanup');
      }
    } catch (e, stackTrace) {
      print('Error cleaning up conversations: $e');
      print('Stack trace: $stackTrace');
    }
  }
  
  // ==================== Points of Interest (POIs) ====================
  
  /// Get a specific POI by ID.
  Future<Map<String, dynamic>?> getPOI(String poiId) async {
    try {
      final snapshot = await _database.ref('pois/$poiId').get();
      if (snapshot.exists) {
        final data = _toMap(snapshot.value);
        if (data != null) {
          data['id'] = poiId;
          return data;
        }
      }
    } catch (e) {
      print('Error getting POI: $e');
    }
    return null;
  }
  
  /// Get all POIs (for client-side distance filtering).
  Future<List<Map<String, dynamic>>> getAllPOIs() async {
    try {
      final snapshot = await _database.ref('pois').get();
      
      if (!snapshot.exists) return [];
      
      final data = _toMap(snapshot.value);
      if (data == null) return [];
      
      final pois = <Map<String, dynamic>>[];
      
      data.forEach((key, value) {
        final poi = _toMap(value);
        if (poi != null) {
          poi['id'] = key;
          pois.add(poi);
        }
      });
      
      return pois;
    } catch (e) {
      print('Error getting all POIs: $e');
      return [];
    }
  }
  
  /// Get POIs by type.
  Future<List<Map<String, dynamic>>> getPOIsByType(String type) async {
    try {
      final snapshot = await _database
          .ref('pois')
          .orderByChild('type')
          .equalTo(type)
          .get();
      
      if (!snapshot.exists) return [];
      
      final data = _toMap(snapshot.value);
      if (data == null) return [];
      
      final pois = <Map<String, dynamic>>[];
      
      data.forEach((key, value) {
        final poi = _toMap(value);
        if (poi != null) {
          poi['id'] = key;
          pois.add(poi);
        }
      });
      
      return pois;
    } catch (e) {
      print('Error getting POIs by type: $e');
      return [];
    }
  }
  
  /// Listen to a specific POI for real-time updates.
  Stream<DatabaseEvent> listenToPOI(String poiId) {
    return _database.ref('pois/$poiId').onValue;
  }
  
  /// Save or update a POI (for admin use).
  Future<void> savePOI(String poiId, Map<String, dynamic> data) async {
    data['lastUpdated'] = ServerValue.timestamp;
    await _database.ref('pois/$poiId').set(data);
  }
  
  // ==================== Context for AI ====================
  
  /// Build context object to pass to Gemini AI.
  /// Includes user preferences, recent conversation summary, and relevant POIs.
  Future<Map<String, dynamic>> buildContextForAI(String userId, {double? latitude, double? longitude}) async {
    final context = <String, dynamic>{};
    
    try {
      // Get accessibility settings
      final settings = await getAccessibilitySettings(userId);
      context['accessibilitySettings'] = settings;
      
      // Get recent conversations (last 10 messages for context)
      final conversations = await getRecentConversations(userId);
      if (conversations.isNotEmpty) {
        final recentMessages = conversations.take(10).toList();
        context['recentConversations'] = recentMessages.map((c) => {
          'role': c['role']?.toString() ?? 'unknown',
          'content': c['content']?.toString() ?? '',
        }).toList();
      }
      
      // Get nearby POIs if location provided
      if (latitude != null && longitude != null) {
        final allPOIs = await getAllPOIs();
        // Filter POIs within ~1km (simple approximation)
        final nearbyPOIs = allPOIs.where((poi) {
          final coordsValue = poi['coords'];
          if (coordsValue == null) return false;
          
          // Handle coords as a Map
          final coords = _toMap(coordsValue);
          if (coords == null) return false;
          
          final lat = coords['latitude'];
          final lng = coords['longitude'];
          if (lat == null || lng == null) return false;
          
          // Convert to num safely
          final latNum = lat is num ? lat : double.tryParse(lat.toString());
          final lngNum = lng is num ? lng : double.tryParse(lng.toString());
          if (latNum == null || lngNum == null) return false;
          
          // Simple distance check (~0.01 degrees ≈ 1km)
          final latDiff = (latNum - latitude).abs();
          final lngDiff = (lngNum - longitude).abs();
          return latDiff < 0.01 && lngDiff < 0.01;
        }).toList();
        
        if (nearbyPOIs.isNotEmpty) {
          context['nearbyPOIs'] = nearbyPOIs.map((p) => {
            'name': p['name']?.toString() ?? '',
            'type': p['type']?.toString() ?? '',
            'description': p['description']?.toString() ?? '',
            'accessibilityFeatures': _toMap(p['accessibilityFeatures']) ?? {},
            'safetyNotes': p['safetyNotes']?.toString() ?? '',
          }).toList();
        }
      }
    } catch (e) {
      print('Error building context for AI: $e');
    }
    
    return context;
  }
}
