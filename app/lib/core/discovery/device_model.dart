import 'dart:convert';

/// Represents a discovered device on the local network.
class DiscoveredDevice {
  final String id;
  final String name;
  final String host;
  final int port;
  final String role;
  DateTime lastSeen;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.role = 'receiver',
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get endpoint => '$host:$port';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'port': port,
        'role': role,
      };

  String encode() => jsonEncode(toJson());

  static DiscoveredDevice? tryParse(String raw, String remoteAddress) {
    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        final name = data['name'] as String? ?? 'Bilinmeyen Cihaz';
        final port = data['port'] as int? ?? 8788;
        final role = data['role'] as String? ?? 'receiver';
        final id = data['id'] as String? ?? '$remoteAddress:$port';
        return DiscoveredDevice(
          id: id,
          name: name,
          host: remoteAddress,
          port: port,
          role: role,
        );
      }
    } catch (_) {}
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
