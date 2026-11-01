import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/goals/data/goal_repository.dart';
import 'package:reclaim_app/features/goals/domain/goal_models.dart';
import 'package:uuid/uuid.dart';

import '../../helpers.dart';

void main() {
  group('progress', () {
    test('fraction and remaining are capped at the target', () {
      const half = GoalProgress(targetCents: 2000000, savedCents: 840000);
      expect(half.fraction, closeTo(0.42, 1e-9));
      expect(half.remainingCents, 1160000);
      expect(half.isReached, isFalse);

      const over = GoalProgress(targetCents: 1000, savedCents: 1500);
      expect((over.fraction, over.remainingCents, over.isReached), (1.0, 0, true));
    });

    test('monthly amount counts the current month and rounds up', () {
      const p = GoalProgress(targetCents: 120000, savedCents: 0);
      final now = DateTime(2026, 10, 29);
      // October to March is 6 months: R1 200 / 6 = R200.
      expect(p.monthlyNeededCents(targetDate: DateTime(2027, 3, 1), now: now), 20000);
      expect(const GoalProgress(targetCents: 100, savedCents: 0).monthlyNeededCents(targetDate: DateTime(2027), now: now), 25); // Oct to Jan: 4 months
    });

    test('no monthly amount without a future date, or once reached', () {
      const p = GoalProgress(targetCents: 1000, savedCents: 0);
      final now = DateTime(2026, 10, 29);
      expect(p.monthlyNeededCents(targetDate: null, now: now), isNull);
      expect(p.monthlyNeededCents(targetDate: DateTime(2026, 10, 1), now: now), isNull);
      expect(const GoalProgress(targetCents: 10, savedCents: 10).monthlyNeededCents(targetDate: DateTime(2027), now: now), isNull);
    });
  });

  test('available estimated savings never goes negative', () {
    expect(availableEstimatedSavingsCents(moneyKeptCents: 50000, movedToGoalsCents: 20000), 30000);
    expect(availableEstimatedSavingsCents(moneyKeptCents: 10000, movedToGoalsCents: 20000), 0);
    expect(availableEstimatedSavingsCents(moneyKeptCents: null, movedToGoalsCents: 0), isNull);
  });

  group('repository', () {
    late AppDatabase db;
    late GoalRepository repo;

    setUp(() {
      db = createTestDatabase();
      repo = GoalRepository(db, const Uuid(), () => testNow);
    });

    tearDown(() => db.close());

    test('goals are created, edited and deleted along with their contributions', () async {
      final id = await repo.addGoal(GoalInput(
        name: '  Car deposit ',
        category: GoalCategory.car,
        targetCents: 2000000,
        targetDate: DateTime(2027, 6, 15, 18, 30),
      ));
      var goal = (await repo.watchGoal(id).first)!;
      expect(goal.name, 'Car deposit');
      expect(goal.targetDate, DateTime(2027, 6, 15));

      await repo.addContribution(id, 50000, ContributionSource.manual);
      await repo.addContribution(id, 25000, ContributionSource.estimatedSavings);
      expect(await repo.watchContributions().first, hasLength(2));

      await repo.updateGoal(id, const GoalInput(name: 'Car', category: GoalCategory.car, targetCents: 1500000));
      goal = (await repo.watchGoal(id).first)!;
      expect((goal.name, goal.targetCents, goal.targetDate), ('Car', 1500000, null));

      await repo.deleteGoal(id);
      expect(await repo.watchGoals().first, isEmpty);
      expect(await repo.watchContributions().first, isEmpty, reason: 'contributions cascade with the goal');
    });

    test('invalid goals and contributions are refused', () async {
      expect(() => repo.addGoal(const GoalInput(name: ' ', category: GoalCategory.car, targetCents: 100)), throwsArgumentError);
      expect(() => repo.addGoal(const GoalInput(name: 'Car', category: GoalCategory.car, targetCents: 0)), throwsArgumentError);
      final id = await repo.addGoal(const GoalInput(name: 'Car', category: GoalCategory.car, targetCents: 100));
      expect(() => repo.addContribution(id, 0, ContributionSource.manual), throwsArgumentError);
    });
  });
}
