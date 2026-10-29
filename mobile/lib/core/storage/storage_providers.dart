import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

part 'storage_providers.g.dart';

/// Opened in main() (it needs the key from secure storage first) and injected via override.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => throw UnimplementedError('appDatabaseProvider must be overridden at startup.');

@Riverpod(keepAlive: true)
Uuid uuid(Ref ref) => const Uuid();

/// Injectable clock, so tests can pin "now".
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;
