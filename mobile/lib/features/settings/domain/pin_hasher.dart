import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 for the app-lock PIN. The hash lives in OS secure storage, so this is a
/// second layer: even someone who extracts it can't cheaply try every PIN.
abstract final class PinHasher {
  static const iterations = 100000;
  static const _saltLength = 16;
  static const _keyLength = 32;

  static final _pin = RegExp(r'^\d{4,8}$');

  static bool isValidPin(String pin) => _pin.hasMatch(pin);

  /// Returns `{iterations}.{base64 salt}.{base64 hash}`.
  static String hash(String pin, {int iterations = iterations, Random? random}) {
    final rng = random ?? Random.secure();
    final salt = Uint8List.fromList(List.generate(_saltLength, (_) => rng.nextInt(256)));
    final derived = _pbkdf2(utf8.encode(pin), salt, iterations);
    return '$iterations.${base64Encode(salt)}.${base64Encode(derived)}';
  }

  static bool verify(String pin, String stored) {
    final parts = stored.split('.');
    if (parts.length != 3) return false;
    final iterations = int.tryParse(parts[0]);
    if (iterations == null || iterations <= 0) return false;
    try {
      final salt = base64Decode(parts[1]);
      final expected = base64Decode(parts[2]);
      return _constantTimeEquals(_pbkdf2(utf8.encode(pin), salt, iterations), expected);
    } on FormatException {
      return false;
    }
  }

  /// RFC 8018 PBKDF2 with HMAC-SHA256, producing a single 32-byte block.
  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, password);
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < _keyLength; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
