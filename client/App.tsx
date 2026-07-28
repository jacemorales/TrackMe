import React, { useState, useEffect, useRef } from 'react';
import {
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  Alert,
  Dimensions,
  ActivityIndicator,
  TextInput,
  Platform,
} from 'react-native';
import MapView, { Marker, Polyline, PROVIDER_GOOGLE, Region } from 'react-native-maps';
import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';
import { io, Socket } from 'socket.io-client';

// Define the name of our background location tracking task
const BACKGROUND_LOCATION_TASK_NAME = 'background-location-tracking';

// Backend server URL (Use localhost or local IP during Expo development)
// For Android Emulator, 10.0.2.2 points to host machine. For iOS, localhost works.
const BACKEND_URL = Platform.OS === 'android' ? 'http://10.0.2.2:3000' : 'http://localhost:3000';

// In-Memory listener store to bridge background updates to the UI when active
let liveUIUpdateListener: ((coords: Location.LocationObjectCoords) => void) | null = null;

// Define interfaces
interface LatLng {
  latitude: number;
  longitude: number;
}

// ---------------------------------------------------------
// 1. TaskManager Background Location Registration
// ---------------------------------------------------------
TaskManager.defineTask(BACKGROUND_LOCATION_TASK_NAME, async ({ data, error }) => {
  if (error) {
    console.error(`[Background Task Error]: ${error.message}`);
    return;
  }

  if (data) {
    const { locations } = data as { locations: Location.LocationObject[] };
    if (locations && locations.length > 0) {
      const location = locations[0];
      const { latitude, longitude, speed, heading, accuracy } = location.coords;
      const timestamp = location.timestamp;

      console.log(`[Background GPS]: Lat: ${latitude}, Lng: ${longitude}, Speed: ${speed}, Accuracy: ${accuracy}`);

      // Push update to backend WebSocket
      try {
        const socket = io(BACKEND_URL, { forceNew: true });
        socket.emit('locationUpdate', {
          latitude,
          longitude,
          speed,
          heading,
          timestamp,
          deviceId: 'Device-Expo-Client',
        });
        // Close temporary background socket connection to save resources
        setTimeout(() => socket.disconnect(), 1000);
      } catch (err) {
        console.error('[Background Socket Error]:', err);
      }

      // If app is currently in the foreground, update the UI coordinates live
      if (liveUIUpdateListener) {
        liveUIUpdateListener(location.coords);
      }
    }
  }
});

// Polyline decoder utility function (implements Google Maps Polyline Algorithm)
function decodePolyline(encoded: string): LatLng[] {
  const points: LatLng[] = [];
  let index = 0, len = encoded.length;
  let lat = 0, lng = 0;

  while (index < len) {
    let b, shift = 0, result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlat = ((result & 1) ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlng = ((result & 1) ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    points.push({
      latitude: lat / 1E5,
      longitude: lng / 1E5,
    });
  }
  return points;
}

// Helper to calculate distance in KM between two points (Haversine formula)
function getHaversineDistance(coords1: LatLng, coords2: LatLng): number {
  const toRad = (value: number) => (value * Math.PI) / 180;
  const R = 6371; // Earth's radius in km
  const dLat = toRad(coords2.latitude - coords1.latitude);
  const dLon = toRad(coords2.longitude - coords1.longitude);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(coords1.latitude)) * Math.cos(toRad(coords2.latitude)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

export default function App() {
  const mapRef = useRef<MapView>(null);
  const socketRef = useRef<Socket | null>(null);

  // Map state
  const [currentLocation, setCurrentLocation] = useState<LatLng | null>(null);
  const [destination, setDestination] = useState<LatLng | null>(null);
  const [routePolyline, setRoutePolyline] = useState<LatLng[]>([]);
  const [isTracking, setIsTracking] = useState<boolean>(false);
  const [loadingRoute, setLoadingRoute] = useState<boolean>(false);

  // Address Inputs (Simulated Geocoding for prototype)
  const [startInput, setStartInput] = useState<string>('San Francisco, CA');
  const [destInput, setDestInput] = useState<string>('Los Angeles, CA');

  // Route metrics
  const [remainingDistance, setRemainingDistance] = useState<string>('--');
  const [eta, setEta] = useState<string>('--');

  // Initial region (Defaulting to SF)
  const [region, setRegion] = useState<Region>({
    latitude: 37.7749,
    longitude: -122.4194,
    latitudeDelta: 0.0922,
    longitudeDelta: 0.0421,
  });

  // ---------------------------------------------------------
  // 2. Request Foreground & Background Location Permissions
  // ---------------------------------------------------------
  useEffect(() => {
    (async () => {
      // 1. Foreground Location Permission
      const { status: fgStatus } = await Location.requestForegroundPermissionsAsync();
      if (fgStatus !== 'granted') {
        Alert.alert(
          'Permission Required',
          'Foreground location permission is necessary to render your location on the map.'
        );
        return;
      }

      // Get initial position
      try {
        const location = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.Balanced,
        });
        const coords = {
          latitude: location.coords.latitude,
          longitude: location.coords.longitude,
        };
        setCurrentLocation(coords);
        setRegion({
          ...coords,
          latitudeDelta: 0.05,
          longitudeDelta: 0.05,
        });
      } catch (err) {
        console.warn('Could not retrieve current location immediately:', err);
      }

      // 2. Background Location Permission (Crucial for minimizing the app)
      const { status: bgStatus } = await Location.requestBackgroundPermissionsAsync();
      if (bgStatus !== 'granted') {
        Alert.alert(
          'Background Tracking Recommended',
          'Background permission is needed to stream location updates continuously when the screen is locked.'
        );
      }
    })();
  }, []);

  // ---------------------------------------------------------
  // 3. Socket.io Client Connection Setup
  // ---------------------------------------------------------
  useEffect(() => {
    socketRef.current = io(BACKEND_URL);

    socketRef.current.on('connect', () => {
      console.log('[Socket] Connected to backend server.');
    });

    socketRef.current.on('locationBroadcast', (data: any) => {
      // Receive updates from backend (e.g. if another dashboard client updates or echoes)
      console.log('[Socket Broadcast Received]:', data);
    });

    return () => {
      if (socketRef.current) {
        socketRef.current.disconnect();
      }
    };
  }, []);

  // ---------------------------------------------------------
  // 4. Register Foreground UI Update Listener
  // ---------------------------------------------------------
  useEffect(() => {
    liveUIUpdateListener = (coords) => {
      const updatedPos = { latitude: coords.latitude, longitude: coords.longitude };
      setCurrentLocation(updatedPos);

      // Animate map to follow the user during live tracking
      if (mapRef.current) {
        mapRef.current.animateToRegion({
          ...updatedPos,
          latitudeDelta: 0.02,
          longitudeDelta: 0.02,
        }, 1000);
      }

      // Recalculate remaining distance & simple ETA assuming average speed of 60 km/h (1 km/min)
      if (destination) {
        const distKm = getHaversineDistance(updatedPos, destination);
        setRemainingDistance(`${distKm.toFixed(1)} km`);
        const etaMinutes = Math.round(distKm / (60 / 60)); // Assumes 60 km/h speed
        setEta(`${etaMinutes} mins`);
      }
    };

    return () => {
      liveUIUpdateListener = null;
    };
  }, [destination]);

  // ---------------------------------------------------------
  // 5. Fetch Route Polylines via Google Maps Directions API
  // ---------------------------------------------------------
  const fetchDirections = async () => {
    if (!startInput || !destInput) {
      Alert.alert('Error', 'Please fill in both Starting Point and Destination.');
      return;
    }

    setLoadingRoute(true);
    try {
      // Mock Route Coordinate fetch if API keys are not supplied yet
      // This is a failsafe to demonstrate route plotting and let users test UI immediately
      const mockRouteSFtoLA = [
        { latitude: 37.7749, longitude: -122.4194 }, // SF
        { latitude: 36.1699, longitude: -115.1398 }, // Las Vegas (as an intermediate step)
        { latitude: 34.0522, longitude: -118.2437 }, // LA
      ];

      // In real scenarios, call Directions API:
      // const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${encodeURIComponent(startInput)}&destination=${encodeURIComponent(destInput)}&key=YOUR_API_KEY`;
      // const res = await fetch(url);
      // const json = await res.json();
      // const points = decodePolyline(json.routes[0].overview_polyline.points);
      // setRoutePolyline(points);

      // Fallback Demo:
      setCurrentLocation(mockRouteSFtoLA[0]);
      setDestination(mockRouteSFtoLA[2]);
      setRoutePolyline(mockRouteSFtoLA);

      setRemainingDistance('614 km');
      setEta('5 hours 45 mins');

      // Center map
      if (mapRef.current) {
        mapRef.current.animateToRegion({
          latitude: (mockRouteSFtoLA[0].latitude + mockRouteSFtoLA[2].latitude) / 2,
          longitude: (mockRouteSFtoLA[0].longitude + mockRouteSFtoLA[2].longitude) / 2,
          latitudeDelta: 4.5,
          longitudeDelta: 4.5,
        }, 1000);
      }

    } catch (err: any) {
      Alert.alert('Directions Error', err.message || 'Could not fetch directions');
    } finally {
      setLoadingRoute(false);
    }
  };

  // ---------------------------------------------------------
  // 6. Toggle Tracking Start/Stop
  // ---------------------------------------------------------
  const handleToggleTracking = async () => {
    if (isTracking) {
      // Stop tracking
      const hasStarted = await Location.hasStartedLocationUpdatesAsync(BACKGROUND_LOCATION_TASK_NAME);
      if (hasStarted) {
        await Location.stopLocationUpdatesAsync(BACKGROUND_LOCATION_TASK_NAME);
      }
      setIsTracking(false);
      Alert.alert('Tracking Stopped', 'Background GPS updates have been paused.');
    } else {
      // Verify permissions first
      const { status: fgStatus } = await Location.getForegroundPermissionsAsync();
      const { status: bgStatus } = await Location.getBackgroundPermissionsAsync();

      if (fgStatus !== 'granted' || bgStatus !== 'granted') {
        Alert.alert(
          'Permissions Missing',
          'Ensure foreground and background location permissions are set to "Always Allow" in Settings.'
        );
        return;
      }

      // Start tracking
      try {
        await Location.startLocationUpdatesAsync(BACKGROUND_LOCATION_TASK_NAME, {
          accuracy: Location.Accuracy.BestForNavigation,
          timeInterval: 5000,      // Minimum delay between updates in milliseconds
          distanceInterval: 10,    // Update only if device moves 10 meters
          deferredUpdatesInterval: 5000,
          deferredUpdatesDistance: 10,
          foregroundService: {
            notificationTitle: 'TrackMe Active GPS',
            notificationBody: 'TrackMe is calculating your ETA and streaming real-time metrics.',
            notificationColor: '#4A90E2',
          },
        });
        setIsTracking(true);
        Alert.alert('Tracking Active', 'Real-time coordinates are streaming in the background!');
      } catch (err: any) {
        console.error('Failed to start location updates:', err);
        Alert.alert('Error', 'Failed to register background location tracking task.');
      }
    }
  };

  return (
    <View style={styles.container}>
      {/* Route and Destination Selector Panel */}
      <View style={styles.inputPanel}>
        <Text style={styles.titleText}>TrackMe Routing Setup</Text>
        <TextInput
          style={styles.input}
          value={startInput}
          onChangeText={setStartInput}
          placeholder="Start Point (e.g. San Francisco)"
        />
        <TextInput
          style={styles.input}
          value={destInput}
          onChangeText={setDestInput}
          placeholder="Destination (e.g. Los Angeles)"
        />
        <TouchableOpacity style={styles.routeButton} onPress={fetchDirections}>
          {loadingRoute ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.buttonText}>Draw Route Polylines</Text>
          )}
        </TouchableOpacity>
      </View>

      {/* Main Google Map View */}
      <MapView
        ref={mapRef}
        provider={PROVIDER_GOOGLE}
        style={styles.map}
        initialRegion={region}
        showsUserLocation={true}
        showsMyLocationButton={true}
      >
        {/* Draw Live Location Marker manually */}
        {currentLocation && (
          <Marker
            coordinate={currentLocation}
            title="Current Location"
            description="Active GPS Position"
            pinColor="#4A90E2"
          />
        )}

        {/* Draw Destination Point Marker */}
        {destination && (
          <Marker
            coordinate={destination}
            title="Destination"
            description="Point B"
            pinColor="#E24A4A"
          />
        )}

        {/* Draw route polyline overlay */}
        {routePolyline.length > 0 && (
          <Polyline
            coordinates={routePolyline}
            strokeWidth={5}
            strokeColor="#4A90E2"
          />
        )}
      </MapView>

      {/* Bottom Status & Background Control HUD */}
      <View style={styles.hudPanel}>
        <View style={styles.metricsRow}>
          <View style={styles.metricItem}>
            <Text style={styles.metricLabel}>Distance Left</Text>
            <Text style={styles.metricValue}>{remainingDistance}</Text>
          </View>
          <View style={styles.metricItem}>
            <Text style={styles.metricLabel}>Remaining ETA</Text>
            <Text style={styles.metricValue}>{eta}</Text>
          </View>
        </View>

        <TouchableOpacity
          style={[styles.trackButton, isTracking ? styles.stopButton : styles.startButton]}
          onPress={handleToggleTracking}
        >
          <Text style={styles.trackButtonText}>
            {isTracking ? '■ Stop Tracking' : '▶ Start Background Tracking'}
          </Text>
        </TouchableOpacity>

        {/* Live Status Indicator */}
        <View style={styles.statusRow}>
          <View style={[styles.statusDot, isTracking ? styles.statusActive : styles.statusInactive]} />
          <Text style={styles.statusText}>
            {isTracking ? 'GPS Stream Active (Background Enabled)' : 'Tracking Suspended'}
          </Text>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  inputPanel: {
    position: 'absolute',
    top: Platform.OS === 'ios' ? 50 : 30,
    left: 10,
    right: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.95)',
    borderRadius: 8,
    padding: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
    zIndex: 10,
  },
  titleText: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
    color: '#333',
  },
  input: {
    height: 40,
    borderColor: '#ddd',
    borderWidth: 1,
    borderRadius: 4,
    marginBottom: 8,
    paddingHorizontal: 10,
    backgroundColor: '#fff',
  },
  routeButton: {
    backgroundColor: '#4A90E2',
    padding: 10,
    borderRadius: 4,
    alignItems: 'center',
  },
  buttonText: {
    color: '#fff',
    fontWeight: 'bold',
  },
  map: {
    width: Dimensions.get('window').width,
    height: Dimensions.get('window').height,
  },
  hudPanel: {
    position: 'absolute',
    bottom: Platform.OS === 'ios' ? 40 : 20,
    left: 10,
    right: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.95)',
    borderRadius: 8,
    padding: 15,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
    zIndex: 10,
  },
  metricsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  metricItem: {
    flex: 1,
    alignItems: 'center',
  },
  metricLabel: {
    fontSize: 12,
    color: '#666',
    textTransform: 'uppercase',
  },
  metricValue: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
    marginTop: 4,
  },
  trackButton: {
    paddingVertical: 12,
    borderRadius: 6,
    alignItems: 'center',
    marginBottom: 8,
  },
  startButton: {
    backgroundColor: '#2ecc71',
  },
  stopButton: {
    backgroundColor: '#e74c3c',
  },
  trackButtonText: {
    color: '#fff',
    fontWeight: 'bold',
    fontSize: 16,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  statusDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginRight: 6,
  },
  statusActive: {
    backgroundColor: '#2ecc71',
  },
  statusInactive: {
    backgroundColor: '#95a5a6',
  },
  statusText: {
    fontSize: 12,
    color: '#666',
  },
});
