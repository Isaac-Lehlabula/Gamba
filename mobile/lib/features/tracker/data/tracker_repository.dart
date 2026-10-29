import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../dashboard/domain/dashboard.dart';
import '../../onboarding/data/profile_repository.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../domain/money.dart';

part 'tracker_repository.g.dart';

/// The fields of an entry as entered on the form.
class EntryInput {
  const EntryInput({
    required this.type,
    required this.amountCents,
    required this.occurredAt,
    required this.gamblingType,
    this.platformName,
    this.notes,
  });

  final GamblingEntryType type;
  final int amountCents;
  final DateTime occurredAt;
  final GamblingType gamblingType;
  final String? platformName;
  final String? notes;
}

class TrackerRepository {
  TrackerRepository(this._db, this._uuid, this._now);

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// Newest first.
  Stream<List<GamblingEntry>> watchEntries() => (_db.select(_db.gamblingEntries)
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt), (t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Future<GamblingEntry?> find(String id) =>
      (_db.select(_db.gamblingEntries)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Platform names already used, most recent first, with case variants collapsed.
  Stream<List<String>> watchPlatformNames() => watchEntries().map((entries) {
        final seen = <String>{};
        return [
          for (final e in entries)
            if (e.platformName case final name? when seen.add(name.toLowerCase())) name,
        ];
      });

  Future<String> add(EntryInput input) async {
    _validate(input);
    final id = _uuid.v4();
    final now = _now();
    await _db.into(_db.gamblingEntries).insert(
          GamblingEntriesCompanion.insert(
            id: id,
            entryType: input.type,
            amountCents: input.amountCents,
            occurredAt: input.occurredAt,
            gamblingType: input.gamblingType,
            platformName: Value(_clean(input.platformName)),
            notes: Value(_clean(input.notes)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> update(String id, EntryInput input) async {
    _validate(input);
    await (_db.update(_db.gamblingEntries)..where((t) => t.id.equals(id))).write(
      GamblingEntriesCompanion(
        entryType: Value(input.type),
        amountCents: Value(input.amountCents),
        occurredAt: Value(input.occurredAt),
        gamblingType: Value(input.gamblingType),
        platformName: Value(_clean(input.platformName)),
        notes: Value(_clean(input.notes)),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<void> delete(String id) => (_db.delete(_db.gamblingEntries)..where((t) => t.id.equals(id))).go();

  void _validate(EntryInput input) {
    if (input.amountCents <= 0 || input.amountCents > maxAmountCents) {
      throw ArgumentError('Amount is out of range.');
    }
    // Same ten-minute clock allowance as the backend.
    if (input.occurredAt.isAfter(_now().add(const Duration(minutes: 10)))) {
      throw ArgumentError('An entry cannot be dated in the future.');
    }
  }

  static String? _clean(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

@Riverpod(keepAlive: true)
TrackerRepository trackerRepository(Ref ref) =>
    TrackerRepository(ref.watch(appDatabaseProvider), ref.watch(uuidProvider), ref.watch(clockProvider));

@riverpod
Stream<List<GamblingEntry>> gamblingEntries(Ref ref) => ref.watch(trackerRepositoryProvider).watchEntries();

@riverpod
Stream<List<String>> platformNames(Ref ref) => ref.watch(trackerRepositoryProvider).watchPlatformNames();

@riverpod
Future<GamblingEntry?> gamblingEntry(Ref ref, String id) => ref.watch(trackerRepositoryProvider).find(id);

/// Null until the profile and entries have loaded, or before onboarding sets a start date.
@riverpod
DashboardSummary? dashboard(Ref ref) {
  final start = ref.watch(profileProvider).value?.startDate;
  final entries = ref.watch(gamblingEntriesProvider).value;
  if (start == null || entries == null) return null;

  return DashboardSummary.compute(
    start: start,
    entries: [for (final e in entries) (type: e.entryType, amountCents: e.amountCents, occurredAt: e.occurredAt)],
    usualMonthlySpendRands: ref.watch(latestOnboardingProvider).value?.approxMonthlySpendRands,
    now: ref.watch(clockProvider)(),
  );
}
