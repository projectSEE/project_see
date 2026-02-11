import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'tts_service.dart';

/// Navigation step with voice-friendly instructions
class NavigationStep {
  final String instruction;
  final String distance;
  final String duration;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final String maneuver;

  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    this.maneuver = '',
  });

  /// Convert to blind-friendly voice instruction
  String toVoiceInstruction() {
    String voice = instruction;
    
    // Add distance info
    voice = '$distance后，$voice';
    
    // Add safety warnings based on maneuver
    if (maneuver.contains('turn')) {
      voice += '。转弯时注意周围车辆。';
    } else if (maneuver.contains('cross')) {
      voice += '。过马路时请确认安全。';
    }
    
    return voice;
  }
}

/// Place search result
class PlaceResult {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final bool wheelchairAccessible;

  PlaceResult({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.wheelchairAccessible = false,
  });
}

/// Navigation service for blind-friendly navigation
class NavigationService {
  static const String _apiKey = 'AIzaSyAYJLNWbHgn-Fv5x-L04Ejob3OUudZ0usA';
  
  final TTSService _ttsService = TTSService();
  
  List<NavigationStep> _steps = [];
  int _currentStepIndex = 0;
  bool _isNavigating = false;
  StreamSubscription<Position>? _positionSubscription;
  
  // Callbacks
  Function(NavigationStep)? onStepChanged;
  Function(String)? onArrived;
  Function(Position)? onPositionUpdate;

  bool get isNavigating => _isNavigating;
  NavigationStep? get currentStep => 
      _steps.isNotEmpty && _currentStepIndex < _steps.length 
          ? _steps[_currentStepIndex] 
          : null;

  /// Initialize TTS
  Future<void> initialize() async {
    await _ttsService.initialize();
  }

  /// Get current location with timeout and fallback
  Future<Position?> getCurrentLocation() async {
    try {
      debugPrint('📍 Checking location service...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('📍 Location service enabled: $serviceEnabled');
      
      if (!serviceEnabled) {
        await _ttsService.speak('位置服务未开启，正在打开设置');
        debugPrint('❌ Location service not enabled, opening settings...');
        
        // Prompt user to enable location service
        final opened = await Geolocator.openLocationSettings();
        debugPrint('📍 Opened location settings: $opened');
        
        // Wait a moment for user to enable
        await Future.delayed(const Duration(seconds: 2));
        
        // Check again
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          await _ttsService.speak('请开启位置服务后点击重试');
          return null;
        }
      }

      debugPrint('📍 Checking location permission...');
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('📍 Permission status: $permission');
      
      if (permission == LocationPermission.denied) {
        debugPrint('📍 Requesting permission...');
        permission = await Geolocator.requestPermission();
        debugPrint('📍 Permission after request: $permission');
        if (permission == LocationPermission.denied) {
          await _ttsService.speak('位置权限被拒绝');
          return null;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        await _ttsService.speak('位置权限被永久拒绝，请在设置中开启');
        return null;
      }

      debugPrint('📍 Getting current position...');
      
      // Try to get current position with timeout
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Location request timed out');
          },
        );
        debugPrint('✅ Got position: ${position.latitude}, ${position.longitude}');
        return position;
      } on TimeoutException {
        debugPrint('⏰ getCurrentPosition timed out, trying last known...');
        // Fallback to last known position
        final lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          debugPrint('✅ Using last known position: ${lastPosition.latitude}, ${lastPosition.longitude}');
          await _ttsService.speak('使用上次已知位置');
          return lastPosition;
        }
        await _ttsService.speak('获取位置超时，请确保在室外或靠近窗户');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Location error: $e');
      await _ttsService.speak('获取位置失败');
      return null;
    }
  }

  /// Search for places nearby using Places API (New)
  Future<List<PlaceResult>> searchPlaces(String query, {Position? near}) async {
    try {
      Position? location = near ?? await getCurrentLocation();
      if (location == null) {
        debugPrint('❌ Search failed: Could not get location');
        return [];
      }

      debugPrint('🔍 Searching for: $query at ${location.latitude}, ${location.longitude}');

      // Use Places API (New) - Text Search endpoint
      final url = Uri.parse('https://places.googleapis.com/v1/places:searchText');
      
      final requestBody = json.encode({
        'textQuery': query,
        'locationBias': {
          'circle': {
            'center': {
              'latitude': location.latitude,
              'longitude': location.longitude,
            },
            'radius': 1000.0,
          },
        },
        'maxResultCount': 10,
        'languageCode': 'zh-CN',
      });

      debugPrint('🌐 API URL: $url');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.accessibilityOptions',
        },
        body: requestBody,
      );
      
      debugPrint('📥 Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('❌ HTTP error: ${response.statusCode} - ${response.body}');
        // Fallback to old API if new API fails
        return _searchPlacesOldApi(query, location);
      }

      final data = json.decode(response.body);
      final places = data['places'] as List? ?? [];
      debugPrint('✅ Found ${places.length} results');

      return places.map((place) {
        final accessibilityOptions = place['accessibilityOptions'] ?? {};
        return PlaceResult(
          placeId: place['id'] ?? '',
          name: place['displayName']?['text'] ?? '',
          address: place['formattedAddress'] ?? '',
          lat: place['location']?['latitude'] ?? 0.0,
          lng: place['location']?['longitude'] ?? 0.0,
          wheelchairAccessible: accessibilityOptions['wheelchairAccessibleEntrance'] == true,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ Search error: $e');
      await _ttsService.speak('搜索出错');
      return [];
    }
  }
  
  /// Fallback to old Places API if new API fails
  Future<List<PlaceResult>> _searchPlacesOldApi(String query, Position location) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
        'location=${location.latitude},${location.longitude}'
        '&radius=1000'
        '&keyword=$query'
        '&language=zh-CN'
        '&key=$_apiKey'
      );

      final response = await http.get(url);
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      if (data['status'] != 'OK') return [];

      final results = data['results'] as List? ?? [];
      return results.map((place) => PlaceResult(
        placeId: place['place_id'] ?? '',
        name: place['name'] ?? '',
        address: place['vicinity'] ?? '',
        lat: place['geometry']?['location']?['lat'] ?? 0.0,
        lng: place['geometry']?['location']?['lng'] ?? 0.0,
      )).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get walking route to destination
  Future<List<NavigationStep>> getRoute(
    double originLat, double originLng,
    double destLat, double destLng,
  ) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=$originLat,$originLng'
        '&destination=$destLat,$destLng'
        '&mode=walking'
        '&language=zh-CN'
        '&key=$_apiKey'
      );

      final response = await http.get(url);
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final routes = data['routes'] as List? ?? [];
      if (routes.isEmpty) return [];

      final legs = routes[0]['legs'] as List? ?? [];
      if (legs.isEmpty) return [];

      final steps = legs[0]['steps'] as List? ?? [];

      return steps.map((step) => NavigationStep(
        instruction: _stripHtml(step['html_instructions'] ?? ''),
        distance: step['distance']?['text'] ?? '',
        duration: step['duration']?['text'] ?? '',
        startLat: step['start_location']?['lat'] ?? 0.0,
        startLng: step['start_location']?['lng'] ?? 0.0,
        endLat: step['end_location']?['lat'] ?? 0.0,
        endLng: step['end_location']?['lng'] ?? 0.0,
        maneuver: step['maneuver'] ?? '',
      )).toList();
    } catch (e) {
      debugPrint('❌ Route error: $e');
      return [];
    }
  }

  /// Start navigation to destination
  Future<void> startNavigation(PlaceResult destination) async {
    final position = await getCurrentLocation();
    if (position == null) return;

    _steps = await getRoute(
      position.latitude, position.longitude,
      destination.lat, destination.lng,
    );

    if (_steps.isEmpty) {
      await _ttsService.speak('无法获取导航路线');
      return;
    }

    _currentStepIndex = 0;
    _isNavigating = true;

    // Announce start
    await _ttsService.speak('开始导航到${destination.name}。共${_steps.length}步。');
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Announce first step
    _speakCurrentStep();

    // Start location tracking
    _startLocationTracking();
  }

  /// Start tracking location for navigation updates
  void _startLocationTracking() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen((Position position) {
      onPositionUpdate?.call(position);
      _checkArrivalAtStep(position);
    });
  }

  /// Check if user arrived at current step
  void _checkArrivalAtStep(Position position) {
    if (!_isNavigating || _steps.isEmpty) return;

    final step = _steps[_currentStepIndex];
    final distance = Geolocator.distanceBetween(
      position.latitude, position.longitude,
      step.endLat, step.endLng,
    );

    // Within 10 meters of step end point
    if (distance < 10) {
      _currentStepIndex++;
      
      if (_currentStepIndex >= _steps.length) {
        // Arrived at destination
        _isNavigating = false;
        _ttsService.speak('已到达目的地');
        onArrived?.call('已到达目的地');
        stopNavigation();
      } else {
        // Move to next step
        _speakCurrentStep();
        onStepChanged?.call(_steps[_currentStepIndex]);
      }
    }
  }

  /// Speak current navigation step
  void _speakCurrentStep() {
    if (_steps.isEmpty || _currentStepIndex >= _steps.length) return;
    final step = _steps[_currentStepIndex];
    _ttsService.speak(step.toVoiceInstruction());
  }

  /// Repeat current instruction
  void repeatInstruction() {
    _speakCurrentStep();
  }

  /// Skip to next step
  void nextStep() {
    if (_currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
      _speakCurrentStep();
      onStepChanged?.call(_steps[_currentStepIndex]);
    }
  }

  /// Stop navigation
  void stopNavigation() {
    _isNavigating = false;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _steps = [];
    _currentStepIndex = 0;
  }

  /// Strip HTML tags from text
  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  /// Dispose resources
  void dispose() {
    stopNavigation();
    _ttsService.dispose();
  }
}
