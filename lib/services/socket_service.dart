import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/telemetry_data.dart';

class SocketService {
  IO.Socket? _socket;
  final _connectionController = StreamController<bool>.broadcast();
  final _telemetryController = StreamController<TelemetryData>.broadcast();
  final _logController = StreamController<String>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<TelemetryData> get telemetryStream => _telemetryController.stream;
  Stream<String> get logStream => _logController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String url) {
    disconnect();

    _addLog('Connecting to backend socket: $url');

    try {
      _socket = IO.io(
        url,
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(10)
            .setReconnectionDelay(2000)
            .build(),
      );

      _socket?.onConnect((_) {
        _addLog('Socket connected successfully [ID: ${_socket?.id}]');
        _connectionController.add(true);
      });

      _socket?.onDisconnect((_) {
        _addLog('Socket disconnected');
        _connectionController.add(false);
      });

      _socket?.onConnectError((err) {
        _addLog('Socket connection error: $err');
        _connectionController.add(false);
      });

      _socket?.onError((err) {
        _addLog('Socket error: $err');
      });

      _socket?.on('locationBroadcast', (data) {
        _addLog('Received locationBroadcast: $data');
        if (data is Map<String, dynamic>) {
          try {
            final telemetry = TelemetryData.fromJson(data);
            _telemetryController.add(telemetry);
          } catch (e) {
            _addLog('Error parsing broadcast telemetry: $e');
          }
        }
      });
    } catch (e) {
      _addLog('Failed to initialize socket: $e');
      _connectionController.add(false);
    }
  }

  void emitLocationUpdate(TelemetryData telemetry) {
    if (_socket != null && _socket!.connected) {
      final json = telemetry.toJson();
      _socket!.emit('locationUpdate', json);
      _addLog('Emitted locationUpdate: ${telemetry.latitude.toStringAsFixed(4)}, ${telemetry.longitude.toStringAsFixed(4)}');
    } else {
      _addLog('Socket not connected. Telemetry dropped or pending reconnection.');
    }
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _logController.add('[$timestamp] $message');
  }

  void disconnect() {
    if (_socket != null) {
      _socket?.clearListeners();
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
      _connectionController.add(false);
    }
  }

  void dispose() {
    disconnect();
    _connectionController.close();
    _telemetryController.close();
    _logController.close();
  }
}
