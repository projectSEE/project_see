import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/navigation_service.dart';
import '../services/location_awareness_service.dart';
import '../services/tts_service.dart';

/// Accessible navigation screen for blind users
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final NavigationService _navService = NavigationService();
  final LocationAwarenessService _awarenessService = LocationAwarenessService();
  final TTSService _ttsService = TTSService();
  final TextEditingController _searchController = TextEditingController();

  GoogleMapController? _mapController;
  Position? _currentPosition;
  List<PlaceResult> _searchResults = [];
  PlaceResult? _selectedDestination;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isSearching = false;
  bool _isLoadingRoute = false;
  bool _hasLocationPermission = false;
  String _locationError = '';
  List<NearbyPOI> _nearbyPOIs = [];
  String _lastAnnouncement = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _navService.initialize();
    await _ttsService.initialize();

    // Request location permission first
    final permissionGranted = await _requestLocationPermission();
    if (!permissionGranted) {
      setState(() {
        _locationError = 'Location permission is required for navigation';
      });
      return;
    }

    _currentPosition = await _navService.getCurrentLocation();
    if (_currentPosition != null) {
      setState(() {
        _markers.add(
          Marker(
            markerId: const MarkerId('current'),
            position: LatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
            infoWindow: const InfoWindow(title: 'Your Location'),
          ),
        );
      });
    } else {
      setState(() {
        _locationError = 'Unable to get current location';
      });
      await _ttsService.speak(
        'Unable to get current location. Please check if location services are enabled.',
      );
      return;
    }

    // Set up callbacks
    _navService.onStepChanged = (step) {
      setState(() {});
    };

    _navService.onArrived = (message) {
      _showArrivedDialog(message);
    };

    _navService.onPositionUpdate = (position) {
      setState(() {
        _currentPosition = position;
      });
    };

    // Set up awareness service
    await _awarenessService.initialize();
    _awarenessService.onPOIsFound = (pois) {
      setState(() => _nearbyPOIs = pois);
    };
    _awarenessService.onAnnouncement = (text) {
      setState(() => _lastAnnouncement = text);
    };

    await _ttsService.speak(
      'Navigation screen is open. Enter a destination or start explore mode.',
    );
  }

  /// Request location permission with user-friendly messages
  Future<bool> _requestLocationPermission() async {
    await _ttsService.speak('Requesting location permission');

    // Check current permission status
    var status = await Permission.locationWhenInUse.status;
    debugPrint('📍 Location permission status: $status');

    if (status.isGranted) {
      setState(() => _hasLocationPermission = true);
      return true;
    }

    if (status.isDenied) {
      // Request permission
      status = await Permission.locationWhenInUse.request();
      debugPrint('📍 Permission after request: $status');
    }

    if (status.isGranted) {
      setState(() => _hasLocationPermission = true);
      await _ttsService.speak('Location permission granted');
      return true;
    }

    if (status.isPermanentlyDenied) {
      await _ttsService.speak(
        'Location permission permanently denied. Please enable it in settings.',
      );
      // Show dialog to open settings
      if (mounted) {
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Location Permission Required'),
                content: const Text(
                  'Please enable location permission in settings to use navigation.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      openAppSettings();
                    },
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
        );
      }
      return false;
    }

    await _ttsService.speak(
      'Location permission denied. Navigation is unavailable.',
    );
    return false;
  }

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    await _ttsService.speak('Searching for $query');

    final results = await _navService.searchPlaces(query);

    setState(() {
      _searchResults = results;
      _isSearching = false;
    });

    if (results.isEmpty) {
      await _ttsService.speak('No results found');
    } else {
      await _ttsService.speak(
        'Found ${results.length} results. ${results.first.name}',
      );
    }
  }

  Future<void> _selectDestination(PlaceResult place) async {
    setState(() {
      _selectedDestination = place;
      _searchResults = [];
      _isLoadingRoute = true;

      // Add destination marker
      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(place.lat, place.lng),
          infoWindow: InfoWindow(title: place.name),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    });

    await _ttsService.speak('Selected ${place.name}. Getting route.');

    // Get route
    if (_currentPosition != null) {
      final steps = await _navService.getRoute(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        place.lat,
        place.lng,
      );

      if (steps.isNotEmpty) {
        // Draw route polyline
        final points =
            steps.map((s) => LatLng(s.startLat, s.startLng)).toList();
        points.add(LatLng(steps.last.endLat, steps.last.endLng));

        setState(() {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: points,
              color: Colors.black,
              width: 5,
            ),
          );
          _isLoadingRoute = false;
        });

        // Zoom to fit route
        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(_getBounds(points), 50),
        );
      }
    }

    setState(() => _isLoadingRoute = false);
  }

  LatLngBounds _getBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _startNavigation() async {
    if (_selectedDestination == null) return;
    await _navService.startNavigation(_selectedDestination!);
    setState(() {});
  }

  void _stopNavigation() {
    _navService.stopNavigation();
    setState(() {
      _polylines.clear();
      _markers.removeWhere((m) => m.markerId.value == 'destination');
      _selectedDestination = null;
    });
    _ttsService.speak('Navigation stopped');
  }

  void _showArrivedDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('🎉 Arrived'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _stopNavigation();
                },
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_navService.isNavigating)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopNavigation,
              tooltip: 'Stop Navigation',
            ),
        ],
      ),
      body: Column(
        children: [
          // Explore mode button
          if (!_navService.isNavigating && !_awarenessService.isExploring)
            _buildExploreButton(),

          // Explore mode panel
          if (_awarenessService.isExploring) _buildExplorePanel(),

          // Search bar (only when not exploring)
          if (!_awarenessService.isExploring) _buildSearchBar(),

          // Search results
          if (_searchResults.isNotEmpty) _buildSearchResults(),

          // Map
          Expanded(child: _buildMap()),

          // Navigation controls
          if (_selectedDestination != null && !_navService.isNavigating)
            _buildStartButton(),

          if (_navService.isNavigating) _buildNavigationPanel(),
        ],
      ),
    );
  }

  Widget _buildExploreButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFF5F5F5),
      child: ElevatedButton.icon(
        onPressed: () {
          _awarenessService.startExploring();
          setState(() {});
        },
        icon: const Icon(Icons.explore),
        label: const Text('Start Explore Mode — auto-announce surroundings'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildExplorePanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.explore, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Explore Mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _awarenessService.stopExploring();
                  setState(() => _nearbyPOIs.clear());
                },
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Stop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),

          // Last announcement
          if (_lastAnnouncement.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _lastAnnouncement,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],

          // Nearby POIs count
          const SizedBox(height: 8),
          Text(
            '${_nearbyPOIs.length} places found nearby',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search destination...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onSubmitted: _searchPlaces,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed:
                _isSearching
                    ? null
                    : () => _searchPlaces(_searchController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            child:
                _isSearching
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : const Text('Search'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final place = _searchResults[index];
          return ListTile(
            leading: const Icon(Icons.place, color: Colors.black),
            title: Text(place.name),
            subtitle: Text(place.address),
            onTap: () => _selectDestination(place),
          );
        },
      ),
    );
  }

  Widget _buildMap() {
    // Show error message if there's a location error
    if (_locationError.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _locationError,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _locationError = '');
                  _initialize();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentPosition == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Getting location...'),
          ],
        ),
      );
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        zoom: 16,
      ),
      onMapCreated: (controller) => _mapController = controller,
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
    );
  }

  Widget _buildStartButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        onPressed: _isLoadingRoute ? null : _startNavigation,
        icon: const Icon(Icons.navigation),
        label: Text('Start navigation to ${_selectedDestination!.name}'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildNavigationPanel() {
    final step = _navService.currentStep;
    if (step == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current instruction
          Text(
            step.instruction,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${step.distance} · ${step.duration}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 16),

          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Repeat button
              ElevatedButton.icon(
                onPressed: _navService.repeatInstruction,
                icon: const Icon(Icons.replay),
                label: const Text('Repeat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),

              // Next step button
              ElevatedButton.icon(
                onPressed: _navService.nextStep,
                icon: const Icon(Icons.skip_next),
                label: const Text('Next'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),

              // Stop button
              ElevatedButton.icon(
                onPressed: _stopNavigation,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _navService.dispose();
    _awarenessService.dispose();
    _ttsService.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
