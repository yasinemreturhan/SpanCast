import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Cryptographic PIN challenge-response utilities.
///
/// PIN is never transmitted in plaintext across the network.
/// The server sends a random salt, and the client responds with:
/// HMAC-SHA256(key = pin, message = saltHex) encoded as hex.
class PinProof {
  /// Computes HMAC-SHA256(pin, saltHex) matching the Go and JS implementations.
  static String compute(String pin, String saltHex) {
    final key = utf8.encode(pin);
    final bytes = utf8.encode(saltHex);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  /// Generates a cryptographically secure random salt of [byteLength] bytes (hex-encoded).
  static String generateSalt([int byteLength = 16]) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Constant-time comparison of two hex strings to prevent timing attacks.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
