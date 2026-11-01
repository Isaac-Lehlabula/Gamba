import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../../urges/data/urge_repository.dart';
import '../../urges/domain/urge_models.dart';
import '../domain/insights.dart';
import '../domain/journal_models.dart';

part 'journal_repository.g.dart';

class JournalInput {
  const JournalInput({
    required this.occurredAt,
    this.mood,
    this.trigger,
    this.urgeIntensity,
    this.outcome,
    this.helped = const {},
    this.note,
  });

  final DateTime occurredAt;
  final int? mood;
  final TriggerType? trigger;
  final int? urgeIntensity;
  final JournalOutcome? outcome;
  final Set<CopingStrategy> helped;
  final String? note;

  /// An entry needs at least something in it.
  bool get isEmpty =>
      mood == null && trigger == null && urgeIntensity == null && outcome == null && helped.isEmpty && (note?.trim().isEmpty ?? true);
}

class JournalRepository {
  JournalRepository(this._db, this._uuid, this._now);

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// Newest first.
  Stream<List<JournalEntry>> watchEntries() => (_db.select(_db.journalEntries)
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt), (t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Future<JournalEntry?> find(String id) => (_db.select(_db.journalEntries)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> add(JournalInput input) async {
    final c = _validate(input);
    final id = _uuid.v4();
    final now = _now();
    await _db.into(_db.journalEntries).insert(c.copyWith(id: Value(id), createdAt: Value(now), updatedAt: Value(now)));
    return id;
  }

  Future<void> update(String id, JournalInput input) =>
      (_db.update(_db.journalEntries)..where((t) => t.id.equals(id))).write(_validate(input).copyWith(updatedAt: Value(_now())));

  Future<void> delete(String id) => (_db.delete(_db.journalEntries)..where((t) => t.id.equals(id))).go();

  JournalEntriesCompanion _validate(JournalInput input) {
    if (input.isEmpty) throw ArgumentError('A journal entry needs something in it.');
    for (final v in [input.mood, input.urgeIntensity]) {
      if (v != null && (v < 1 || v > 5)) throw ArgumentError('Scales run from 1 to 5.');
    }
    if (input.occurredAt.isAfter(_now().add(const Duration(minutes: 10)))) throw ArgumentError('Entries cannot be in the future.');
    final note = input.note?.trim();
    if (note != null && note.length > maxJournalNoteLength) throw ArgumentError('Note is too long.');
    return JournalEntriesCompanion(
      occurredAt: Value(input.occurredAt),
      mood: Value(input.mood),
      trigger: Value(input.trigger),
      urgeIntensity: Value(input.urgeIntensity),
      outcome: Value(input.outcome),
      helped: Value(CopingStrategy.values.where(input.helped.contains).toList()),
      note: Value(note == null || note.isEmpty ? null : note),
    );
  }
}

@Riverpod(keepAlive: true)
JournalRepository journalRepository(Ref ref) =>
    JournalRepository(ref.watch(appDatabaseProvider), ref.watch(uuidProvider), ref.watch(clockProvider));

@riverpod
Stream<List<JournalEntry>> journalEntries(Ref ref) => ref.watch(journalRepositoryProvider).watchEntries();

@riverpod
Future<JournalEntry?> journalEntry(Ref ref, String id) => ref.watch(journalRepositoryProvider).find(id);

/// Every recorded urge: journal entries that had one, plus "I feel like gambling" sessions.
@riverpod
List<UrgeEvent> urgeEvents(Ref ref) {
  final journal = ref.watch(journalEntriesProvider).value ?? const <JournalEntry>[];
  final urges = ref.watch(urgeHistoryProvider).value ?? const <Urge>[];
  return [
    for (final j in journal)
      if (j.urgeIntensity != null || (j.outcome != null && j.outcome != JournalOutcome.noUrge))
        UrgeEvent(at: j.occurredAt, trigger: j.trigger, gambled: j.outcome == null ? null : j.outcome == JournalOutcome.gambled, helped: j.helped),
    for (final u in urges)
      if (u.outcome != UrgeOutcome.abandoned)
        UrgeEvent(at: u.startedAt, trigger: u.trigger, gambled: u.outcome == null ? null : u.outcome == UrgeOutcome.gambled),
  ];
}

@riverpod
List<Insight> insights(Ref ref) => Insights.describe(ref.watch(urgeEventsProvider));
