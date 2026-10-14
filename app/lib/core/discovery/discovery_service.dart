import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'device_model.dart';

/// LAN discovery service combining UDP broadcast beacon and peer tracking.
class DiscoveryService {
  static const int beaconPort = 41337;
  static const Duration beaconInterval = Duration(seconds: 2);
  static const Duration peerTtl = Duration(seconds: 8);

  RawDatagramSocket? _listenSocket;
  RawDatagramSocket? _broadcastSocket;
  Timer? _beaconTimer;
  Timer? _cleanupTimer;

  final Map<String, DiscoveredDevice> _devices = {};
  final StreamController<List<DiscoveredDevice>> _controller =
      StreamController<List<DiscoveredDevice>>.broadcast();

  Stream<List<DiscoveredDevice>> get devicesStream => _controller.stream;
  List<DiscoveredDevice> get devices => List.unmodifiable(_devices.values);

  /// Starts listening for other DoScreen devices on the local network.
  Future<void> startListening() async {
    if (_listenSocket != null) return;

    try {
      _listenSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        beaconPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _listenSocket!.broadcastEnabled = true;

      _listenSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _listenSocket?.receive();
          if (datagram != null) {
            _handleDatagram(datagram);
          }
        }
      });

      _cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) => _cleanupStalePeers());
    } catch (e) {
      // Fallback: binding may fail if port is restricted, continue gracefully
    }
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data);
      final remoteIp = datagram.address.address;
      final device = DiscoveredDevice.tryParse(text, remoteIp);
      if (device != null) {
        final existing = _devices[device.id];
        if (existing != null) {
          existing.lastSeen = DateTime.now();
        } else {
          _devices[device.id] = device;
          _notifyListeners();
        }
      }
    } catch (_) {}
  }

  void _cleanupStalePeers() {
    final now = DateTime.now();
    final beforeCount = _devices.length;
    _devices.removeWhere((_, dev) => now.difference(dev.lastSeen) > peerTtl);
    if (_devices.length != beforeCount) {
      _notifyListeners();
    }
  }

  void _notifyListeners() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_devices.values));
    }
  }

  /// Broadcasts this device as an available receiver or sender.
  Future<void> startBroadcasting({
    required String name,
    required int port,
    String role = 'receiver',
    String? id,
  }) async {
    stopBroadcasting();

    final deviceId = id ?? '$name-$port';
    final payload = jsonEncode({
      'id': deviceId,
      'name': name,
      'port': port,
      'role': role,
    });
    final bytes = utf8.encode(payload);

    try {
      _broadcastSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      _broadcastSocket!.broadcastEnabled = true;

      // Broadcast immediately and on periodic interval
      _sendBeacon(bytes);
      _beaconTimer = Timer.periodic(beaconInterval, (_) => _sendBeacon(bytes));
    } catch (_) {}
  }

  void _sendBeacon(List<int> bytes) {
    try {
      // Broadcast to standard IPv4 broadcast address
      _broadcastSocket?.send(
        bytes,
        InternetAddress('255.255.255.255'),
        beaconPort,
      );
    } catch (_) {}
  }

  void stopBroadcasting() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _broadcastSocket?.close();
    _broadcastSocket = null;
  }

  void stopListening() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _listenSocket?.close();
    _listenSocket = null;
    _devices.clear();
    _notifyListeners();
  }

  void dispose() {
    stopBroadcasting();
    stopListening();
    _controller.close();
  }
}
