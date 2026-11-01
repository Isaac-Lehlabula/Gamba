import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/secure_store.dart';
import '../domain/pin_hasher.dart';

part 'app_lock_repository.g.dart';

/// App-lock settings, kept in OS secure storage alongside the database key.
class AppLockRepository {
  AppLockRepository(this._storage, {this.iterations = PinHasher.iterations, this.useIsolate = true});

  static const _pinKey = 'reclaim.lock.pin.v1';
  static const _biometricsKey = 'reclaim.lock.biometrics.v1';

  final SecureStore _storage;

  /// Lowered in tests; PBKDF2 at full strength is deliberately slow.
  final int iterations;

  /// Hashing runs on a background isolate in the app; widget tests run it inline because
  /// their fake clock can't wait on another isolate.
  final bool useIsolate;

  Future<R> _run<A, R>(R Function(A) work, A args) async => useIsolate ? compute(work, args) : work(args);

  Future<bool> isEnabled() async => await _storage.read(_pinKey) != null;

  Future<bool> biometricsEnabled() async => await _storage.read(_biometricsKey) == 'true';

  Future<void> enable(String pin, {required bool biometrics}) async {
    if (!PinHasher.isValidPin(pin)) throw ArgumentError('PIN must be 4 to 8 digits.');
    // Hashing takes a noticeable moment at full strength, so do it off the UI thread.
    final hash = await _run((({String pin, int iterations}) a) => PinHasher.hash(a.pin, iterations: a.iterations), (pin: pin, iterations: iterations));
    await _storage.write(_pinKey, hash);
    await setBiometrics(biometrics);
  }

  Future<void> setBiometrics(bool enabled) => _storage.write(_biometricsKey, '$enabled');

  Future<bool> verify(String pin) async {
    final stored = await _storage.read(_pinKey);
    if (stored == null) return false;
    return _run((({String pin, String stored}) a) => PinHasher.verify(a.pin, a.stored), (pin: pin, stored: stored));
  }

  Future<void> disable() async {
    await _storage.delete(_pinKey);
    await _storage.delete(_biometricsKey);
  }
}

/// Biometric unlock, behind an interface so tests and devices without biometrics behave the same.
abstract interface class BiometricAuth {
  Future<bool> isAvailable();
  Future<bool> authenticate();
}

class LocalBiometricAuth implements BiometricAuth {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(localizedReason: 'Unlock Reclaim', biometricOnly: true, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }
}

@Riverpod(keepAlive: true)
AppLockRepository appLockRepository(Ref ref) => AppLockRepository(ref.watch(secureStoreProvider));

@Riverpod(keepAlive: true)
BiometricAuth biometricAuth(Ref ref) => LocalBiometricAuth();
