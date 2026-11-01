import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../domain/blocker_models.dart';
import 'blocker_platform.dart';

part 'blocker_repositories.g.dart';

class BlocklistRepository {
  BlocklistRepository(this._db, this._dio, this._loadSeed, this._now);

  static const _cursorKey = 'blocklist.since';

  final AppDatabase _db;
  final Dio _dio;
  final Future<String> Function() _loadSeed;
  final DateTime Function() _now;

  /// Every active domain to block, sorted.
  Future<List<String>> activeDomains() async {
    final rows = await (_db.select(_db.blockedDomains)..where((t) => t.isActive.equals(true))).get();
    return [for (final r in rows) r.domain]..sort();
  }

  Stream<List<BlockedDomain>> watchCustom() => (_db.select(_db.blockedDomains)
        ..where((t) => t.source.equalsValue(BlockedDomainSource.custom))
        ..orderBy([(t) => OrderingTerm.asc(t.domain)]))
      .watch();

  Stream<int> watchActiveCount() {
    final count = _db.blockedDomains.domain.count();
    return (_db.selectOnly(_db.blockedDomains)
          ..addColumns([count])
          ..where(_db.blockedDomains.isActive.equals(true)))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  /// Loads the bundled starter list the first time, so blocking works before any sync.
  Future<void> ensureSeeded() async {
    final any = await (_db.select(_db.blockedDomains)..limit(1)).getSingleOrNull();
    if (any != null) return;
    final seed = parseSeedDomains(await _loadSeed());
    final now = _now();
    await _db.batch((b) {
      for (final domain in seed) {
        b.insert(
          _db.blockedDomains,
          BlockedDomainsCompanion.insert(domain: domain, source: BlockedDomainSource.seed, updatedAt: now),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Fetches changes from the public blocklist (no account needed). Server rows replace seed
  /// rows of the same domain; the user's own domains are never touched.
  Future<int> syncFromServer() async {
    final since = await _setting(_cursorKey);
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/blocklist',
      queryParameters: {'since': ?since},
      options: AuthInterceptor.anonymous(),
    );
    final body = response.data!;
    final items = (body['items'] as List<Object?>).cast<Map<String, dynamic>>();
    final now = _now();
    await _db.transaction(() async {
      for (final item in items) {
        final domain = normalizeDomain(item['domain'] as String);
        if (domain == null) continue;
        final existing = await (_db.select(_db.blockedDomains)..where((t) => t.domain.equals(domain))).getSingleOrNull();
        if (existing?.source == BlockedDomainSource.custom) continue;
        await _db.into(_db.blockedDomains).insertOnConflictUpdate(
              BlockedDomainsCompanion.insert(
                domain: domain,
                source: BlockedDomainSource.server,
                isActive: Value(item['isActive'] as bool),
                updatedAt: now,
              ),
            );
      }
      if (body['nextSince'] case final String next) await _setSetting(_cursorKey, next);
      await _setSetting('blocklist.syncedAt', now.toUtc().toIso8601String());
    });
    return items.length;
  }

  Future<DateTime?> lastSyncedAt() async => DateTime.tryParse(await _setting('blocklist.syncedAt') ?? '');

  /// Adds a domain the user wants blocked. Returns the normalised domain, or null if invalid.
  Future<String?> addCustom(String input) async {
    final domain = normalizeDomain(input);
    if (domain == null) return null;
    await _db.into(_db.blockedDomains).insertOnConflictUpdate(
          BlockedDomainsCompanion.insert(domain: domain, source: BlockedDomainSource.custom, updatedAt: _now()),
        );
    return domain;
  }

  Future<void> removeCustom(String domain) => (_db.delete(_db.blockedDomains)
        ..where((t) => t.domain.equals(domain) & t.source.equalsValue(BlockedDomainSource.custom)))
      .go();

  Future<String?> _setting(String key) async =>
      (await (_db.select(_db.localSettings)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> _setSetting(String key, String value) =>
      _db.into(_db.localSettings).insertOnConflictUpdate(LocalSettingsCompanion.insert(key: key, value: value));
}

/// The protection lock: while active, protection can't be switched off and the user's own
/// domains can't be removed. Ending it early takes a request plus a 24-hour wait.
class ProtectionRepository {
  ProtectionRepository(this._db, this._uuid, this._now);

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _now;

  Stream<ProtectionLock?> watchLock() => (_db.select(_db.protectionLocks)
        ..where((t) => t.status.equalsValue(ProtectionLockStatus.active))
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
        ..limit(1))
      .watchSingleOrNull();

  Stream<ProtectionRemovalRequest?> watchPendingRemoval() => (_db.select(_db.protectionRemovalRequests)
        ..where((t) => t.status.equalsValue(RemovalRequestStatus.pending))
        ..limit(1))
      .watchSingleOrNull();

  /// Whether a lock is in force right now. A lock past its end date ends itself here.
  Future<bool> isLocked() async {
    final lock = await (_db.select(_db.protectionLocks)..where((t) => t.status.equalsValue(ProtectionLockStatus.active))).getSingleOrNull();
    if (lock == null) return false;
    if (!_now().isBefore(lock.expiresAt)) {
      await _end(lock.id);
      return false;
    }
    return true;
  }

  Future<void> startLock(int days) async {
    if (!ProtectionRules.durations.contains(days)) throw ArgumentError('Unsupported lock length.');
    if (await isLocked()) throw StateError('Protection is already locked.');
    final now = _now();
    await _db.into(_db.protectionLocks).insert(
          ProtectionLocksCompanion.insert(
            id: _uuid.v4(),
            durationDays: days,
            startedAt: now,
            // Calendar days, so a daylight-saving change doesn't shorten or lengthen the lock.
            expiresAt: DateTime(now.year, now.month, now.day + days, now.hour, now.minute, now.second),
            status: ProtectionLockStatus.active,
          ),
        );
  }

  Future<void> requestRemoval() async {
    final lock = await (_db.select(_db.protectionLocks)..where((t) => t.status.equalsValue(ProtectionLockStatus.active))).getSingleOrNull();
    if (lock == null) return;
    if (await watchPendingRemoval().first != null) return;
    final now = _now();
    await _db.into(_db.protectionRemovalRequests).insert(
          ProtectionRemovalRequestsCompanion.insert(
            id: _uuid.v4(),
            lockId: lock.id,
            requestedAt: now,
            coolingOffEndsAt: now.add(ProtectionRules.coolingOff),
            status: RemovalRequestStatus.pending,
          ),
        );
  }

  Future<void> cancelRemoval() => (_db.update(_db.protectionRemovalRequests)
        ..where((t) => t.status.equalsValue(RemovalRequestStatus.pending)))
      .write(ProtectionRemovalRequestsCompanion(status: const Value(RemovalRequestStatus.cancelled), resolvedAt: Value(_now())));

  /// Ends the lock once the cooling-off has passed. Returns false if it's too early.
  Future<bool> completeRemoval() async {
    final request = await (_db.select(_db.protectionRemovalRequests)
          ..where((t) => t.status.equalsValue(RemovalRequestStatus.pending)))
        .getSingleOrNull();
    if (request == null || _now().isBefore(request.coolingOffEndsAt)) return false;
    await _db.transaction(() async {
      await (_db.update(_db.protectionRemovalRequests)..where((t) => t.id.equals(request.id)))
          .write(ProtectionRemovalRequestsCompanion(status: const Value(RemovalRequestStatus.completed), resolvedAt: Value(_now())));
      await _end(request.lockId);
    });
    return true;
  }

  Future<void> _end(String lockId) => (_db.update(_db.protectionLocks)..where((t) => t.id.equals(lockId)))
      .write(ProtectionLocksCompanion(status: const Value(ProtectionLockStatus.ended), endedAt: Value(_now())));
}

@Riverpod(keepAlive: true)
BlockerPlatform blockerPlatform(Ref ref) => MethodChannelBlocker();

/// Reads the starter blocklist bundled with the app.
@Riverpod(keepAlive: true)
Future<String> Function() blocklistSeedLoader(Ref ref) => () => rootBundle.loadString('assets/blocklist-seed.txt');

@Riverpod(keepAlive: true)
BlocklistRepository blocklistRepository(Ref ref) => BlocklistRepository(
      ref.watch(appDatabaseProvider),
      ref.watch(apiClientProvider),
      ref.watch(blocklistSeedLoaderProvider),
      ref.watch(clockProvider),
    );

@Riverpod(keepAlive: true)
ProtectionRepository protectionRepository(Ref ref) =>
    ProtectionRepository(ref.watch(appDatabaseProvider), ref.watch(uuidProvider), ref.watch(clockProvider));

@riverpod
Stream<List<BlockedDomain>> customDomains(Ref ref) => ref.watch(blocklistRepositoryProvider).watchCustom();

@riverpod
Stream<int> activeDomainCount(Ref ref) => ref.watch(blocklistRepositoryProvider).watchActiveCount();

@riverpod
Stream<ProtectionLock?> protectionLock(Ref ref) => ref.watch(protectionRepositoryProvider).watchLock();

@riverpod
Stream<ProtectionRemovalRequest?> pendingRemoval(Ref ref) => ref.watch(protectionRepositoryProvider).watchPendingRemoval();
