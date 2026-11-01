import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/storage_providers.dart';
import '../../blocker/data/blocker_platform.dart';
import '../../blocker/data/blocker_repositories.dart';
import 'app_lock_repository.dart';

part 'data_wipe_service.g.dart';

/// "Delete everything on this phone": every record, then a VACUUM so deleted pages don't
/// linger in the file, then protection, the app-lock settings and account sign-in. The router sees the
/// profile disappear and returns to the welcome screen.
class DataWipeService {
  DataWipeService(this._db, this._lock, this._tokens, this._blocker);

  final AppDatabase _db;
  final AppLockRepository _lock;
  final TokenStore _tokens;
  final BlockerPlatform _blocker;

  Future<void> wipeEverything() async {
    // Protection and its local log of blocked sites go too; the database wipe below removes
    // the protection lock, so nothing would be left keeping it on.
    await _blocker.stop();
    await _blocker.clearBlockedLog();
    await _blocker.setBlocklist(const []);
    await _db.transaction(() async {
      // Children before parents, so foreign keys are never violated.
      for (final table in _db.allTables.toList().reversed) {
        await _db.delete(table).go();
      }
    });
    await _db.customStatement('VACUUM');
    await _lock.disable();
    // Signs this phone out; the account and its backup are untouched.
    await _tokens.clear();
  }
}

@riverpod
DataWipeService dataWipeService(Ref ref) =>
    DataWipeService(
      ref.watch(appDatabaseProvider),
      ref.watch(appLockRepositoryProvider),
      ref.watch(tokenStoreProvider),
      ref.watch(blockerPlatformProvider),
    );
