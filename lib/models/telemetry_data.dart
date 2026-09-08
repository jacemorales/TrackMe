class TelemetryData {
  final double latitude;
  final double longitude;
  final double? speed;
  final double? heading;
  final double? accuracy;
  final int timestamp;
  final String deviceId;

  TelemetryData({
    required this.latitude,
    required this.longitude,
    this.speed,
    this.heading,
    this.accuracy,
    required this.timestamp,
    required this.deviceId,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
      'timestamp': timestamp,
      'deviceId': deviceId,
    };
  }

  factory TelemetryData.fromJson(Map<String, dynamic> json) {
    return TelemetryData(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      heading: json['heading'] != null ? (json['heading'] as num).toDouble() : null,
      accuracy: json['accuracy'] != null ? (json['accuracy'] as num).toDouble() : null,
      timestamp: json['timestamp'] is int
          ? json['timestamp'] as int
          : (json['timestamp'] as num).toInt(),
      deviceId: json['deviceId']?.toString() ?? 'Unknown-Device',
    );
  }
}
