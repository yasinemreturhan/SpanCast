import 'dart:convert';

/// Represents a message in the signaling protocol.
class SignalMessage {
  final String type;
  final String? from;
  final String? to;
  final String? name;
  final String? pin;
  final String? roomId;
  final String? reason;
  final dynamic payload;

  const SignalMessage({
    required this.type,
    this.from,
    this.to,
    this.name,
    this.pin,
    this.roomId,
    this.reason,
    this.payload,
  });

  factory SignalMessage.fromJson(Map<String, dynamic> json) {
    return SignalMessage(
      type: json['type'] as String? ?? 'error',
      from: json['from'] as String?,
      to: json['to'] as String?,
      name: json['name'] as String?,
      pin: json['pin'] as String?,
      roomId: json['roomId'] as String?,
      reason: json['reason'] as String?,
      payload: json['payload'],
    );
  }

  static SignalMessage? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SignalMessage.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type};
    if (from != null) map['from'] = from;
    if (to != null) map['to'] = to;
    if (name != null) map['name'] = name;
    if (pin != null) map['pin'] = pin;
    if (roomId != null) map['roomId'] = roomId;
    if (reason != null) map['reason'] = reason;
    if (payload != null) map['payload'] = payload;
    return map;
  }

  String encode() => jsonEncode(toJson());

  @override
  String toString() => encode();
}
