import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../tracker/data/tracker_repository.dart';
import '../../tracker/domain/money.dart';
import '../domain/goal_models.dart';

part 'goal_repository.g.dart';

class GoalInput {
  const GoalInput({required this.name, required this.category, required this.targetCents, this.targetDate});

  final String name;
  final GoalCategory category;
  final int targetCents;
  final DateTime? targetDate;
}

/// A goal with its progress, for lists and cards.
class GoalView {
  const GoalView(this.goal, this.progress);

  final RecoveryGoal goal;
  final GoalProgress progress;
}

class GoalRepository {
  GoalRepository(this._db, this._uuid, this._now);

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _now;

  Stream<List<RecoveryGoal>> watchGoals() =>
      (_db.select(_db.recoveryGoals)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();

  Stream<RecoveryGoal?> watchGoal(String id) =>
      (_db.select(_db.recoveryGoals)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// All contributions, newest first.
  Stream<List<GoalContribution>> watchContributions() => (_db.select(_db.goalContributions)
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt), (t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Future<String> addGoal(GoalInput input) async {
    final clean = _validate(input);
    final id = _uuid.v4();
    final now = _now();
    await _db.into(_db.recoveryGoals).insert(
          RecoveryGoalsCompanion.insert(
            id: id,
            name: clean.name,
            category: clean.category,
            targetCents: clean.targetCents,
            targetDate: Value(clean.targetDate),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> updateGoal(String id, GoalInput input) {
    final clean = _validate(input);
    return (_db.update(_db.recoveryGoals)..where((t) => t.id.equals(id))).write(
      RecoveryGoalsCompanion(
        name: Value(clean.name),
        category: Value(clean.category),
        targetCents: Value(clean.targetCents),
        targetDate: Value(clean.targetDate),
        updatedAt: Value(_now()),
      ),
    );
  }

  /// Removes the goal and, through the foreign key cascade, its contributions.
  Future<void> deleteGoal(String id) => (_db.delete(_db.recoveryGoals)..where((t) => t.id.equals(id))).go();

  Future<void> addContribution(String goalId, int amountCents, ContributionSource source) async {
    if (amountCents <= 0 || amountCents > maxAmountCents) throw ArgumentError('Amount is out of range.');
    final now = _now();
    await _db.into(_db.goalContributions).insert(
          GoalContributionsCompanion.insert(
            id: _uuid.v4(),
            goalId: goalId,
            amountCents: amountCents,
            source: source,
            occurredAt: now,
            createdAt: now,
          ),
        );
  }

  Future<void> deleteContribution(String id) =>
      (_db.delete(_db.goalContributions)..where((t) => t.id.equals(id))).go();

  static GoalInput _validate(GoalInput input) {
    final name = input.name.trim();
    if (name.isEmpty || name.length > maxGoalNameLength) throw ArgumentError('Goal name must be 1 to $maxGoalNameLength characters.');
    if (input.targetCents <= 0 || input.targetCents > maxAmountCents) throw ArgumentError('Target is out of range.');
    final date = input.targetDate;
    return GoalInput(
      name: name,
      category: input.category,
      targetCents: input.targetCents,
      targetDate: date == null ? null : DateTime(date.year, date.month, date.day),
    );
  }
}

@Riverpod(keepAlive: true)
GoalRepository goalRepository(Ref ref) =>
    GoalRepository(ref.watch(appDatabaseProvider), ref.watch(uuidProvider), ref.watch(clockProvider));

@riverpod
Stream<List<RecoveryGoal>> goals(Ref ref) => ref.watch(goalRepositoryProvider).watchGoals();

@riverpod
Stream<RecoveryGoal?> goal(Ref ref, String id) => ref.watch(goalRepositoryProvider).watchGoal(id);

@riverpod
Stream<List<GoalContribution>> goalContributions(Ref ref) => ref.watch(goalRepositoryProvider).watchContributions();

/// Goals with progress, oldest first. Null while loading.
@riverpod
List<GoalView>? goalViews(Ref ref) {
  final goals = ref.watch(goalsProvider).value;
  final contributions = ref.watch(goalContributionsProvider).value;
  if (goals == null || contributions == null) return null;

  final saved = <String, int>{};
  for (final c in contributions) {
    saved[c.goalId] = (saved[c.goalId] ?? 0) + c.amountCents;
  }
  return [for (final g in goals) GoalView(g, GoalProgress(targetCents: g.targetCents, savedCents: saved[g.id] ?? 0))];
}

/// Estimated savings not yet moved into a goal; null when there's no estimate to draw on.
@riverpod
int? availableEstimatedSavings(Ref ref) {
  final contributions = ref.watch(goalContributionsProvider).value ?? const <GoalContribution>[];
  return availableEstimatedSavingsCents(
    moneyKeptCents: ref.watch(dashboardProvider)?.moneyKeptCents,
    movedToGoalsCents: contributions
        .where((c) => c.source == ContributionSource.estimatedSavings)
        .fold(0, (sum, c) => sum + c.amountCents),
  );
}
