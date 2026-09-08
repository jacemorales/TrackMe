import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'models/telemetry_data.dart';
import 'services/location_service.dart';
import 'services/routing_service.dart';
import 'services/socket_service.dart';
import 'theme/app_theme.dart';
import 'widgets/custom_marker.dart';
import 'widgets/hud_metric_card.dart';
import 'widgets/logs_drawer.dart';
import 'widgets/settings_modal.dart';

void main() {
  runApp(const TrackMeApp());
}

class TrackMeApp extends StatefulWidget {
  const TrackMeApp({super.key});

  @override
  State<TrackMeApp> createState() => _TrackMeAppState();
}

class _TrackMeAppState extends State<TrackMeApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrackMe Real-Time Tracking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: _themeMode,
      home: MapTrackingScreen(onToggleTheme: _toggleTheme),
    );
  }
}

class MapTrackingScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;

  const MapTrackingScreen({super.key, required this.onToggleTheme});

  @override
  State<MapTrackingScreen> createState() => _MapTrackingScreenState();
}

class _MapTrackingScreenState extends State<MapTrackingScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final SocketService _socketService = SocketService();
  final RoutingService _routingService = RoutingService();

  final TextEditingController _startController =
      TextEditingController(text: 'San Francisco, CA');
  final TextEditingController _destController =
      TextEditingController(text: 'Los Angeles, CA');

  // Socket state
  String _serverUrl = 'http://10.0.2.2:3000';
  bool _isSocketConnected = false;
  final List<String> _logs = [];

  // Tracking & map state
  bool _isTracking = false;
  bool _isLoadingRoute = false;
  bool _followUser = true;

  LatLng _currentPosition = const LatLng(37.7749, -122.4194); // SF default
  LatLng? _destinationPosition;
  List<LatLng> _routePoints = [];

  // Telemetry metrics
  double _currentSpeedKmH = 0.0;
  double _currentHeading = 0.0;
  double _remainingDistanceKm = 0.0;
  double _etaMinutes = 0.0;

  // Search & Map Tile Layer selection
  String _mapTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png'; // Default OSM
  List<PlaceSearchResult> _searchSuggestions = [];

  StreamSubscription<bool>? _socketConnSub;
  StreamSubscription<TelemetryData>? _socketTelemetrySub;
  StreamSubscription<String>? _socketLogSub;

  @override
  void initState() {
    super.initState();
    _setupServices();
    _initUserLocation();
  }

  void _setupServices() {
    _socketService.connect(_serverUrl);

    _socketConnSub = _socketService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isSocketConnected = connected;
        });
      }
    });

    _socketTelemetrySub = _socketService.telemetryStream.listen((telemetry) {
      if (mounted) {
        setState(() {
          // Update live marker from socket broadcast
          _currentPosition = LatLng(telemetry.latitude, telemetry.longitude);
          if (telemetry.speed != null) {
            _currentSpeedKmH = (telemetry.speed! * 3.6); // m/s to km/h
          }
          if (telemetry.heading != null) {
            _currentHeading = telemetry.heading!;
          }
          _recalculateMetrics();
        });
      }
    });

    _socketLogSub = _socketService.logStream.listen((logMsg) {
      if (mounted) {
        setState(() {
          _logs.add(logMsg);
          if (_logs.length > 200) _logs.removeAt(0);
        });
      }
    });
  }

  Future<void> _initUserLocation() async {
    final pos = await _locationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _mapController.move(_currentPosition, 13.0);
      });
    }
  }

  void _toggleTracking() async {
    if (_isTracking) {
      _locationService.stopPositionStream();
      setState(() {
        _isTracking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Background GPS streaming paused.'),
          backgroundColor: Colors.amber,
        ),
      );
    } else {
      final hasPermission = await _locationService.checkAndRequestPermissions();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission was denied.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _isTracking = true;
      });

      _locationService.startPositionStream(
        onPosition: (Position position) {
          if (!mounted) return;

          final newPos = LatLng(position.latitude, position.longitude);
          final speed = position.speed >= 0 ? position.speed : 0.0;
          final heading = position.heading >= 0 ? position.heading : 0.0;

          setState(() {
            _currentPosition = newPos;
            _currentSpeedKmH = speed * 3.6;
            _currentHeading = heading;
            _recalculateMetrics();

            if (_followUser) {
              _mapController.move(newPos, _mapController.camera.zoom);
            }
          });

          // Emit to backend socket server
          final telemetry = TelemetryData(
            latitude: position.latitude,
            longitude: position.longitude,
            speed: speed,
            heading: heading,
            accuracy: position.accuracy,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            deviceId: 'Flutter-Device-${identityHashCode(this)}',
          );

          _socketService.emitLocationUpdate(telemetry);
        },
        onError: (err) {
          setState(() {
            _isTracking = false;
          });
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live GPS streaming active! Broadcasting coordinates...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _recalculateMetrics() {
    if (_destinationPosition != null) {
      final dist = _locationService.calculateDistanceInKm(
        _currentPosition,
        _destinationPosition!,
      );
      _remainingDistanceKm = dist;

      double avgSpeed = _currentSpeedKmH > 10 ? _currentSpeedKmH : 60.0;
      _etaMinutes = (dist / avgSpeed) * 60.0;
    }
  }

  Future<void> _fetchAndDrawRoute() async {
    final startText = _startController.text.trim();
    final destText = _destController.text.trim();

    if (startText.isEmpty || destText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please specify both Start and Destination.')),
      );
      return;
    }

    setState(() {
      _isLoadingRoute = true;
      _searchSuggestions.clear();
    });

    try {
      // 1. Geocode Destination
      final destResults = await _routingService.searchPlaces(destText);
      LatLng destCoord;
      if (destResults.isNotEmpty) {
        destCoord = destResults.first.location;
      } else {
        // Fallback default LA if geocoding fails
        destCoord = const LatLng(34.0522, -118.2437);
      }

      // 2. Geocode Start (or use current live location)
      LatLng startCoord = _currentPosition;
      final startResults = await _routingService.searchPlaces(startText);
      if (startResults.isNotEmpty) {
        startCoord = startResults.first.location;
      }

      // 3. Fetch Route
      final routeDetails = await _routingService.getRoute(startCoord, destCoord);

      setState(() {
        _currentPosition = startCoord;
        _destinationPosition = destCoord;
        _routePoints = routeDetails.points;
        _remainingDistanceKm = routeDetails.distanceKm;
        _etaMinutes = routeDetails.durationMinutes;

        // Fit map bounds to show route
        if (_routePoints.isNotEmpty) {
          final bounds = LatLngBounds.fromPoints(_routePoints);
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(50),
            ),
          );
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Route calculation error: $e')),
      );
    } finally {
      setState(() {
        _isLoadingRoute = false;
      });
    }
  }

  void _swapLocations() {
    final temp = _startController.text;
    _startController.text = _destController.text;
    _destController.text = temp;
    if (_routePoints.isNotEmpty) {
      _fetchAndDrawRoute();
    }
  }

  void _openSettingsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SettingsModal(
        currentServerUrl: _serverUrl,
        onSave: (newUrl) {
          setState(() {
            _serverUrl = newUrl;
          });
          _socketService.connect(_serverUrl);
        },
      ),
    );
  }

  void _openLogsDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LogsDrawerModal(
        logs: _logs,
        onClearLogs: () {
          setState(() {
            _logs.clear();
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _destController.dispose();
    _locationService.stopPositionStream();
    _socketConnSub?.cancel();
    _socketTelemetrySub?.cancel();
    _socketLogSub?.cancel();
    _socketService.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // -------------------------------------------------------------
          // 1. Interactive Map Layer
          // -------------------------------------------------------------
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 12.0,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && _followUser) {
                  setState(() {
                    _followUser = false;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _mapTileUrl,
                userAgentPackageName: 'com.trackme.client',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Live Current Location Marker
                  Marker(
                    point: _currentPosition,
                    width: 80,
                    height: 80,
                    child: CustomMarker(
                      icon: Icons.navigation_rounded,
                      color: AppTheme.primaryColor,
                      label: 'LIVE GPS',
                      isPulsing: _isTracking,
                    ),
                  ),
                  // Destination Marker
                  if (_destinationPosition != null)
                    Marker(
                      point: _destinationPosition!,
                      width: 80,
                      height: 80,
                      child: const CustomMarker(
                        icon: Icons.flag_rounded,
                        color: AppTheme.dangerColor,
                        label: 'POINT B',
                      ),
                    ),
                ],
              ),
            ],
          ),

          // -------------------------------------------------------------
          // 2. Top Navigation & Route Setup Panel
          // -------------------------------------------------------------
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkCardBackground
                      : AppTheme.lightCardBackground,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.radar,
                          color: AppTheme.primaryColor,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'TrackMe',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.black,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const Spacer(),
                        // Socket status badge
                        GestureDetector(
                          onTap: _openSettingsModal,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _isSocketConnected
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isSocketConnected
                                    ? Colors.green
                                    : Colors.red,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isSocketConnected
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isSocketConnected ? 'Socket Active' : 'Offline',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _isSocketConnected
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            isDark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            size: 20,
                          ),
                          onPressed: widget.onToggleTheme,
                          tooltip: 'Toggle Theme',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              TextField(
                                controller: _startController,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Start Point (Point A)',
                                  prefixIcon: Icon(
                                    Icons.my_location,
                                    size: 16,
                                    color: AppTheme.primaryColor,
                                  ),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _destController,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Destination (Point B)',
                                  prefixIcon: Icon(
                                    Icons.location_on,
                                    size: 16,
                                    color: AppTheme.dangerColor,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: _swapLocations,
                          icon: const Icon(Icons.swap_vert),
                          tooltip: 'Swap locations',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Quick route calculate button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _isLoadingRoute ? null : _fetchAndDrawRoute,
                        icon: _isLoadingRoute
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.alt_route, size: 18),
                        label: Text(
                          _isLoadingRoute ? 'Calculating...' : 'Draw Optimal Route',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------
          // 3. Floating Action Buttons (Right Side)
          // -------------------------------------------------------------
          Positioned(
            right: 16,
            bottom: 220,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  backgroundColor:
                      _followUser ? AppTheme.primaryColor : Colors.black87,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    setState(() {
                      _followUser = true;
                      _mapController.move(_currentPosition, 15.0);
                    });
                  },
                  tooltip: 'Recenter on me',
                  child: const Icon(Icons.gps_fixed),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'tile_layer',
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    setState(() {
                      if (_mapTileUrl.contains('openstreetmap')) {
                        _mapTileUrl =
                            'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
                      } else {
                        _mapTileUrl =
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
                      }
                    });
                  },
                  tooltip: 'Toggle Map Style',
                  child: const Icon(Icons.layers_outlined),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'logs',
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  onPressed: _openLogsDrawer,
                  tooltip: 'Telemetry Logs',
                  child: const Icon(Icons.terminal),
                ),
              ],
            ),
          ),

          // -------------------------------------------------------------
          // 4. Bottom Telemetry HUD & Tracking Controls
          // -------------------------------------------------------------
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.darkCardBackground
                    : AppTheme.lightCardBackground,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 15,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Metrics Row 1
                  Row(
                    children: [
                      Expanded(
                        child: HUDMetricCard(
                          icon: Icons.straighten,
                          label: 'Distance Left',
                          value: _remainingDistanceKm > 0
                              ? '${_remainingDistanceKm.toStringAsFixed(1)} km'
                              : '--',
                          accentColor: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: HUDMetricCard(
                          icon: Icons.timer_outlined,
                          label: 'Remaining ETA',
                          value: _etaMinutes > 0
                              ? '${_etaMinutes.round()} mins'
                              : '--',
                          accentColor: AppTheme.secondaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Metrics Row 2
                  Row(
                    children: [
                      Expanded(
                        child: HUDMetricCard(
                          icon: Icons.speed,
                          label: 'Speed',
                          value: '${_currentSpeedKmH.toStringAsFixed(1)} km/h',
                          accentColor: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: HUDMetricCard(
                          icon: Icons.explore_outlined,
                          label: 'Heading',
                          value: '${_currentHeading.round()}°',
                          accentColor: Colors.cyan,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Primary Tracking Toggle Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isTracking
                            ? AppTheme.dangerColor
                            : AppTheme.secondaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _toggleTracking,
                      icon: Icon(
                        _isTracking
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        size: 22,
                      ),
                      label: Text(
                        _isTracking
                            ? 'STOP BACKGROUND TRACKING'
                            : 'START BACKGROUND TRACKING',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
