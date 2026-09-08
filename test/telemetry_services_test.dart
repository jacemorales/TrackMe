import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trackme_client/models/telemetry_data.dart';
import 'package:trackme_client/services/location_service.dart';
import 'package:trackme_client/services/routing_service.dart';

void main() {
  group('TelemetryData Tests', () {
    test('toJson and fromJson serialization works correctly', () {
      final telemetry = TelemetryData(
        latitude: 37.7749,
        longitude: -122.4194,
        speed: 15.5,
        heading: 180.0,
        accuracy: 5.0,
        timestamp: 1620000000000,
        deviceId: 'Test-Device-01',
      );

      final json = telemetry.toJson();
      expect(json['latitude'], 37.7749);
      expect(json['longitude'], -122.4194);
      expect(json['speed'], 15.5);
      expect(json['deviceId'], 'Test-Device-01');

      final deserialized = TelemetryData.fromJson(json);
      expect(deserialized.latitude, 37.7749);
      expect(deserialized.longitude, -122.4194);
      expect(deserialized.speed, 15.5);
      expect(deserialized.heading, 180.0);
      expect(deserialized.deviceId, 'Test-Device-01');
    });
  });

  group('LocationService Tests', () {
    final locationService = LocationService();

    test('calculateDistanceInKm accurately measures distance between SF and LA', () {
      const sf = LatLng(37.7749, -122.4194);
      const la = LatLng(34.0522, -118.2437);

      final distKm = locationService.calculateDistanceInKm(sf, la);
      // Distance between SF and LA is ~550km straight line
      expect(distKm, greaterThan(500));
      expect(distKm, lessThan(600));
    });

    test('calculateDistanceInMeters returns 0 for identical points', () {
      const point = LatLng(37.7749, -122.4194);
      final distMeters = locationService.calculateDistanceInMeters(point, point);
      expect(distMeters, equals(0.0));
    });
  });

  group('RoutingService Fallback Tests', () {
    final routingService = RoutingService();

    test('generateFallbackRoute generates valid points and metrics', () {
      const sf = LatLng(37.7749, -122.4194);
      const la = LatLng(34.0522, -118.2437);

      final routeDetails = routingService.generateFallbackRoute(sf, la);

      expect(routeDetails.points.isNotEmpty, true);
      expect(routeDetails.distanceKm, greaterThan(500));
      expect(routeDetails.durationMinutes, greaterThan(0));
      expect(routeDetails.points.first, equals(sf));
    });
  });
}
