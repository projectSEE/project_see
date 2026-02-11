import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'tts_service.dart';

/// Point of Interest with distance
class NearbyPOI {
  final String name;
  final String type;
  final double lat;
  final double lng;
  final double distance; // in meters
  final String direction; // 前方/左侧/右侧/后方

  NearbyPOI({
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    required this.distance,
    required this.direction,
  });

  String toVoiceAnnouncement() {
    final dist = distance < 100 
        ? '${distance.round()}米' 
        : '${(distance / 100).round() * 100}米';
    return '$direction$dist有$name';
  }
}

/// Location awareness service for real-time environment announcements
class LocationAwarenessService {
  static const String _apiKey = 'AIzaSyAYJLNWbHgn-Fv5x-L04Ejob3OUudZ0usA';
  
  final TTSService _ttsService = TTSService();
  
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  double _lastHeading = 0;
  
  bool _isExploring = false;
  DateTime _lastAnnouncement = DateTime.now();
  Set<String> _announcedPOIs = {}; // Track announced POIs to avoid repetition
  
  // Callbacks
  Function(List<NearbyPOI>)? onPOIsFound;
  Function(String)? onAnnouncement;
  
  bool get isExploring => _isExploring;

  /// Initialize the service
  Future<void> initialize() async {
    await _ttsService.initialize();
  }

  /// Start exploration mode
  Future<void> startExploring() async {
    if (_isExploring) return;
    
    _isExploring = true;
    _announcedPOIs.clear();
    
    await _ttsService.speak('探索模式已开启。我会告诉你周围有什么。');
    
    // Start position tracking
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen(_onPositionUpdate);
    
    // Get initial position and announce
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _onPositionUpdate(position);
  }

  /// Stop exploration mode
  void stopExploring() {
    _isExploring = false;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _announcedPOIs.clear();
    _ttsService.speak('探索模式已关闭');
  }

  /// Handle position updates
  Future<void> _onPositionUpdate(Position position) async {
    if (!_isExploring) return;
    
    // Calculate heading if we have previous position
    if (_lastPosition != null) {
      _lastHeading = _calculateBearing(
        _lastPosition!.latitude, _lastPosition!.longitude,
        position.latitude, position.longitude,
      );
    }
    
    _lastPosition = position;
    
    // Check if enough time passed since last announcement (5 seconds)
    final now = DateTime.now();
    if (now.difference(_lastAnnouncement).inSeconds < 5) return;
    
    // Fetch and announce nearby POIs
    await _fetchAndAnnouncePOIs(position);
    
    _lastAnnouncement = now;
  }

  /// Fetch nearby POIs and announce new ones
  Future<void> _fetchAndAnnouncePOIs(Position position) async {
    try {
      debugPrint('🔍 Fetching POIs at ${position.latitude}, ${position.longitude}');
      
      // Use Places API (New) to search nearby
      final url = Uri.parse('https://places.googleapis.com/v1/places:searchNearby');
      
      final requestBody = json.encode({
        'includedTypes': [
          'restaurant', 'cafe', 'store', 'bank', 'atm',
          'hospital', 'pharmacy', 'bus_station', 'subway_station',
          'convenience_store', 'supermarket', 'gas_station',
        ],
        'maxResultCount': 10,
        'locationRestriction': {
          'circle': {
            'center': {
              'latitude': position.latitude,
              'longitude': position.longitude,
            },
            'radius': 100.0, // 100 meters radius
          },
        },
        'languageCode': 'zh-CN',
      });

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.types,places.location',
        },
        body: requestBody,
      );

      if (response.statusCode != 200) {
        debugPrint('❌ Places API error: ${response.statusCode}');
        return;
      }

      final data = json.decode(response.body);
      final places = data['places'] as List? ?? [];
      
      // Convert to NearbyPOI objects
      final pois = <NearbyPOI>[];
      for (final place in places) {
        final placeLat = place['location']?['latitude'] ?? 0.0;
        final placeLng = place['location']?['longitude'] ?? 0.0;
        
        final distance = Geolocator.distanceBetween(
          position.latitude, position.longitude,
          placeLat, placeLng,
        );
        
        final direction = _getDirection(
          position.latitude, position.longitude,
          placeLat, placeLng,
          _lastHeading,
        );
        
        final types = place['types'] as List? ?? [];
        final typeStr = _getChineseType(types.isNotEmpty ? types.first : '');
        
        pois.add(NearbyPOI(
          name: place['displayName']?['text'] ?? '',
          type: typeStr,
          lat: placeLat,
          lng: placeLng,
          distance: distance,
          direction: direction,
        ));
      }
      
      // Sort by distance
      pois.sort((a, b) => a.distance.compareTo(b.distance));
      
      onPOIsFound?.call(pois);
      
      // Announce new POIs (not announced before)
      final newPOIs = pois.where((p) => !_announcedPOIs.contains(p.name)).take(3).toList();
      
      if (newPOIs.isNotEmpty) {
        final announcements = newPOIs.map((p) => p.toVoiceAnnouncement()).join('。');
        debugPrint('📢 Announcing: $announcements');
        await _ttsService.speak(announcements);
        onAnnouncement?.call(announcements);
        
        // Mark as announced
        for (final poi in newPOIs) {
          _announcedPOIs.add(poi.name);
        }
        
        // Clear old announcements if too many
        if (_announcedPOIs.length > 50) {
          _announcedPOIs = _announcedPOIs.toList().sublist(25).toSet();
        }
      }
      
    } catch (e) {
      debugPrint('❌ Error fetching POIs: $e');
    }
  }

  /// Calculate bearing between two points
  double _calculateBearing(double lat1, double lng1, double lat2, double lng2) {
    final dLng = (lng2 - lng1) * pi / 180;
    final lat1Rad = lat1 * pi / 180;
    final lat2Rad = lat2 * pi / 180;
    
    final x = sin(dLng) * cos(lat2Rad);
    final y = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLng);
    
    return atan2(x, y) * 180 / pi;
  }

  /// Get relative direction (前方/左侧/右侧/后方)
  String _getDirection(double userLat, double userLng, double poiLat, double poiLng, double heading) {
    final bearing = _calculateBearing(userLat, userLng, poiLat, poiLng);
    var relative = bearing - heading;
    
    // Normalize to -180 to 180
    while (relative > 180) relative -= 360;
    while (relative < -180) relative += 360;
    
    if (relative.abs() < 45) return '前方';
    if (relative.abs() > 135) return '后方';
    if (relative > 0) return '右侧';
    return '左侧';
  }

  /// Convert place type to Chinese
  String _getChineseType(String type) {
    const Map<String, String> typeMap = {
      'restaurant': '餐厅',
      'cafe': '咖啡店',
      'store': '商店',
      'bank': '银行',
      'atm': 'ATM',
      'hospital': '医院',
      'pharmacy': '药店',
      'bus_station': '公交站',
      'subway_station': '地铁站',
      'convenience_store': '便利店',
      'supermarket': '超市',
      'gas_station': '加油站',
    };
    return typeMap[type] ?? '地点';
  }

  /// Dispose resources
  void dispose() {
    stopExploring();
    _ttsService.dispose();
  }
}
