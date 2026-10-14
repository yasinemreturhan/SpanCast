import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// AirPlayService — Interacts with the native Android AirPlay 2 receiver engine.
///
/// Enables the Android/TV device to advertise itself as an AirPlay display on the local network.
/// A Mac user can open macOS Control Center -> Screen Mirroring -> "DoScreen TV"
/// and select "Use As Separate Display" (Ayrı Ekran Olarak Kullan) to use the TV as a 2nd desktop monitor!
class AirPlayService {
  static const MethodChannel _channel = MethodChannel('app.doscreen/airplay');

  static final AirPlayService _instance = AirPlayService._internal();
  factory AirPlayService() => _instance;

  AirPlayService._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String _status = 'IDLE'; // IDLE, ADVERTISING, CONNECTED, ERROR
  String get status => _status;

  String? _activeSender;
  String? get activeSender => _activeSender;

  String _deviceName = 'SpanCast TV';
  String get deviceName => _deviceName;

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onAirPlayStateChanged') {
      try {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _updateFromMap(args);
      } catch (e) {
        debugPrint('AirPlayService: Error handling onAirPlayStateChanged: $e');
      }
    }
  }

  void _updateFromMap(Map<String, dynamic> map) {
    _isRunning = map['isRunning'] as bool? ?? false;
    _status = map['status'] as String? ?? 'IDLE';
    _deviceName = map['deviceName'] as String? ?? 'SpanCast TV';
    _activeSender = map['activeSender'] as String?;
    _statusController.add(map);
  }

  /// Starts advertising the AirPlay 2 receiver on the local Wi-Fi/Ethernet network.
  Future<bool> startReceiver({String? name}) async {
    try {
      final res = await _channel.invokeMethod<Map>('startReceiver', {
        'name': name ?? _deviceName,
      });
      if (res != null) {
        _updateFromMap(Map<String, dynamic>.from(res));
      }
      return true;
    } catch (e) {
      debugPrint('AirPlayService: Failed to start receiver: $e');
      return false;
    }
  }

  /// Stops advertising and releases all AirPlay network sockets.
  Future<bool> stopReceiver() async {
    try {
      final res = await _channel.invokeMethod<Map>('stopReceiver');
      if (res != null) {
        _updateFromMap(Map<String, dynamic>.from(res));
      }
      return true;
    } catch (e) {
      debugPrint('AirPlayService: Failed to stop receiver: $e');
      return false;
    }
  }

  /// Fetches the latest status from the native engine.
  Future<void> fetchStatus() async {
    try {
      final res = await _channel.invokeMethod<Map>('getStatus');
      if (res != null) {
        _updateFromMap(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint('AirPlayService: Failed to fetch status: $e');
    }
  }
}
