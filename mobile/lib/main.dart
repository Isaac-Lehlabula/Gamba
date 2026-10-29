import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/storage/app_database.dart';
import 'core/storage/database_key_store.dart';
import 'core/storage/encrypted_connection.dart';
import 'core/storage/storage_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final key = await DatabaseKeyStore(const FlutterSecureStorage()).getOrCreateHexKey();
  final directory = await getApplicationSupportDirectory();
  final database = AppDatabase(openEncryptedDatabase(File(p.join(directory.path, 'reclaim.db')), key));

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: const ReclaimApp(),
    ),
  );
}
