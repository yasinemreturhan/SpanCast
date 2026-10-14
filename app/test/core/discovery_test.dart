import 'package:flutter_test/flutter_test.dart';
import 'package:doscreen/core/discovery/device_model.dart';
import 'package:doscreen/core/discovery/discovery_service.dart';

void main() {
  group('DiscoveredDevice', () {
    test('parses json datagram correctly', () {
      const jsonStr = '{"id":"tv-1","name":"Living Room TV","port":8788,"role":"receiver"}';
      final dev = DiscoveredDevice.tryParse(jsonStr, '192.168.1.55');

      expect(dev, isNotNull);
      expect(dev!.id, 'tv-1');
      expect(dev.name, 'Living Room TV');
      expect(dev.host, '192.168.1.55');
      expect(dev.port, 8788);
      expect(dev.endpoint, '192.168.1.55:8788');
      expect(dev.role, 'receiver');
    });

    test('serializes to json roundtrip', () {
      final dev = DiscoveredDevice(
        id: 'laptop-1',
        name: 'Work Laptop',
        host: '192.168.1.100',
        port: 8788,
      );

      final encoded = dev.encode();
      final parsed = DiscoveredDevice.tryParse(encoded, '192.168.1.100');
      expect(parsed, isNotNull);
      expect(parsed!.id, dev.id);
      expect(parsed.name, dev.name);
    });
  });

  group('DiscoveryService', () {
    test('initializes and disposes cleanly', () async {
      final service = DiscoveryService();
      expect(service.devices, isEmpty);
      await service.startListening();
      service.stopListening();
      service.dispose();
    });
  });
}
