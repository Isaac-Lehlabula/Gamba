import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the local database encryption key in OS-backed secure storage (Android Keystore,
/// iOS Keychain). The key never touches the database or app preferences.
class DatabaseKeyStore {
  DatabaseKeyStore(this._storage);

  static const _keyName = 'reclaim.db.key.v1';

  final FlutterSecureStorage _storage;

  /// Returns the 256-bit key as 64 lowercase hex characters, creating it on first launch.
  Future<String> getOrCreateHexKey() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null) return existing;

    final random = Random.secure();
    final key = List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: _keyName, value: key);
    return key;
  }

  /// Used by "wipe everything on this phone": without the key the old file is unreadable.
  Future<void> delete() => _storage.delete(key: _keyName);
}
