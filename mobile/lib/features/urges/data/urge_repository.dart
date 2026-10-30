import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../domain/urge_models.dart';

part 'urge_repository.g.dart';

class UrgeRepository {
  UrgeRepository(this._db, this._uuid, this._now);

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// Starts a pause. Any earlier urge still open is marked abandoned, so there is only ever
  /// one in progress.
  Future<String> start({required TriggerType trigger, int? intensity, required int minutes}) {
    if (!UrgePause.options.contains(minutes)) throw ArgumentError('Unsupported pause length.');
    if (intensity != null && (intensity < 1 || intensity > 5)) throw ArgumentError('Intensity must be 1 to 5.');

    final id = _uuid.v4();
    final now = _now();
    return _db.transaction(() async {
      await _abandonOpen(now);
      await _db.into(_db.urges).insert(
            UrgesCompanion.insert(
              id: id,
              trigger: trigger,
              intensity: Value(intensity),
              coolingOffMinutes: minutes,
              startedAt: now,
              createdAt: now,
            ),
          );
      return id;
    });
  }

  /// Adds more time to an open urge.
  Future<void> extend(String id) => _db.customUpdate(
        'UPDATE urges SET cooling_off_minutes = cooling_off_minutes + ? WHERE id = ? AND resolved_at IS NULL',
        variables: [Variable.withInt(UrgePause.extensionMinutes), Variable.withString(id)],
        updates: {_db.urges},
      );

  Future<void> resolve(String id, UrgeOutcome outcome) =>
      (_db.update(_db.urges)..where((t) => t.id.equals(id) & t.resolvedAt.isNull())).write(
        UrgesCompanion(outcome: Value(outcome), resolvedAt: Value(_now())),
      );

  Stream<Urge?> watch(String id) => (_db.select(_db.urges)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// The open urge, if one was started recently enough to still be in progress.
  Stream<Urge?> watchActive() => (_db.select(_db.urges)
        ..where((t) => t.resolvedAt.isNull() & t.startedAt.isBiggerThanValue(_now().subtract(UrgePause.staleAfter)))
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
        ..limit(1))
      .watchSingleOrNull();

  /// Newest first.
  Stream<List<Urge>> watchHistory() =>
      (_db.select(_db.urges)..orderBy([(t) => OrderingTerm.desc(t.startedAt)])).watch();

  Future<void> _abandonOpen(DateTime now) => (_db.update(_db.urges)..where((t) => t.resolvedAt.isNull())).write(
        UrgesCompanion(outcome: const Value(UrgeOutcome.abandoned), resolvedAt: Value(now)),
      );
}

@Riverpod(keepAlive: true)
UrgeRepository urgeRepository(Ref ref) =>
    UrgeRepository(ref.watch(appDatabaseProvider), ref.watch(uuidProvider), ref.watch(clockProvider));

@riverpod
Stream<Urge?> urge(Ref ref, String id) => ref.watch(urgeRepositoryProvider).watch(id);

@riverpod
Stream<Urge?> activeUrge(Ref ref) => ref.watch(urgeRepositoryProvider).watchActive();

@riverpod
Stream<List<Urge>> urgeHistory(Ref ref) => ref.watch(urgeRepositoryProvider).watchHistory();
