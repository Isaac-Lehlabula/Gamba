import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

final _hexKey = RegExp(r'^[0-9a-f]{64}$');

/// Opens the on-device database encrypted with SQLite3MultipleCiphers (selected in
/// pubspec.yaml's sqlite3 hook options).
///
/// Fails loudly rather than ever writing plaintext: if the bundled SQLite has no cipher
/// support, or the key is wrong, opening throws.
QueryExecutor openEncryptedDatabase(File file, String hexKey) {
  if (!_hexKey.hasMatch(hexKey)) {
    throw ArgumentError('Database key must be 64 lowercase hex characters.');
  }
  return NativeDatabase.createInBackground(
    file,
    setup: (db) => applyEncryptionKey(db, hexKey),
  );
}

/// Applies the key to a raw connection and checks that encryption is really active.
void applyEncryptionKey(Database db, String hexKey) {
  // The key is validated hex, so interpolating it cannot inject SQL. On a build without
  // encryption this pragma is silently ignored, which the next check catches.
  db.execute("PRAGMA hexkey = '$hexKey'");
  if (db.select('PRAGMA cipher').isEmpty) {
    throw StateError('This SQLite build has no encryption support; refusing to open the database.');
  }
  // Reading the schema fails with "file is not a database" when the key is wrong.
  db.select('SELECT count(*) FROM sqlite_master');
}
