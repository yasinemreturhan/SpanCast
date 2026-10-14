import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages persistent device pairing tokens (TOFU - Trust On First Use)
/// so that users can connect with a single click without re-entering PINs.
class TrustStore {
  static const String _senderTokensKey = 'doscreen_sender_trust_tokens';
  static const String _receiverTrustedKey = 'doscreen_receiver_trusted_senders';

  final SharedPreferences _prefs;

  TrustStore(this._prefs);

  static Future<TrustStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return TrustStore(prefs);
  }

  // --- SENDER STORAGE ---

  /// Retrieves stored trust token for a specific receiver endpoint (host:port).
  String? getToken(String endpoint) {
    final raw = _prefs.getString(_senderTokensKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map[endpoint] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Saves trust token for a receiver endpoint.
  Future<void> saveToken(String endpoint, String token) async {
    final raw = _prefs.getString(_senderTokensKey);
    final map = <String, dynamic>{};
    if (raw != null) {
      try {
        map.addAll(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    map[endpoint] = token;
    await _prefs.setString(_senderTokensKey, jsonEncode(map));
  }

  /// Removes trust token for a receiver endpoint.
  Future<void> removeToken(String endpoint) async {
    final raw = _prefs.getString(_senderTokensKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.remove(endpoint);
      await _prefs.setString(_senderTokensKey, jsonEncode(map));
    } catch (_) {}
  }

  // --- RECEIVER STORAGE ---

  /// Retrieves the list of devices trusted by this receiver.
  List<Map<String, String>> getTrustedDevices() {
    final raw = _prefs.getString(_receiverTrustedKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Records a newly trusted sender on this receiver.
  Future<void> addTrustedDevice(String token, String deviceName) async {
    final list = getTrustedDevices();
    list.removeWhere((d) => d['token'] == token);
    list.add({
      'token': token,
      'name': deviceName,
      'pairedAt': DateTime.now().toIso8601String(),
    });
    await _prefs.setString(_receiverTrustedKey, jsonEncode(list));
  }

  /// Revokes trust for a sender token on this receiver.
  Future<void> revokeTrustedDevice(String token) async {
    final list = getTrustedDevices();
    list.removeWhere((d) => d['token'] == token);
    await _prefs.setString(_receiverTrustedKey, jsonEncode(list));
  }
}
