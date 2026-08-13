import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Security utilities for gateway authentication.
///
/// Uses HMAC-SHA256 to sign every request and validate the signature
/// on the gateway side. Prevents unauthorized devices on the clinic Wi-Fi
/// from sending SMS through the gateway.
class GatewaySecurity {
  GatewaySecurity._();

  /// Generates an HMAC-SHA256 signature for the given payload using the shared secret.
  static String sign(String payload, String secret) {
    final key = utf8.encode(secret);
    final bytes = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  /// Validates that the provided signature matches the expected HMAC-SHA256.
  static bool verify(String payload, String signature, String secret) {
    final expected = sign(payload, secret);
    // Constant-time comparison to prevent timing attacks
    if (expected.length != signature.length) return false;
    var result = 0;
    for (var i = 0; i < expected.length; i++) {
      result |= expected.codeUnitAt(i) ^ signature.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Checks if the given UTC timestamp (milliseconds since epoch) is within
  /// the allowed window (default: 30 seconds).
  static bool isTimestampValid(int timestampMs, {int windowMs = 30000}) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return (now - timestampMs).abs() <= windowMs;
  }

  /// Creates the canonical payload string for signing.
  /// Includes gatewayId, requestId, timestamp, phone, and message hash
  /// to prevent tampering of any field.
  static String buildSignablePayload({
    required String gatewayId,
    required String requestId,
    required int timestamp,
    required String phone,
    required String message,
  }) {
    // Hash the message body to keep the signable string short
    final messageHash = sha256.convert(utf8.encode(message)).toString();
    return '$gatewayId|$requestId|$timestamp|$phone|$messageHash';
  }
}
