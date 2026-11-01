import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/blocker/data/blocker_repositories.dart';
import 'package:reclaim_app/features/goals/data/goal_repository.dart';
import 'package:reclaim_app/features/goals/domain/goal_models.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:reclaim_app/features/tracker/data/tracker_repository.dart';
import 'package:reclaim_app/features/tracker/domain/money.dart';
import 'package:reclaim_app/features/urges/data/urge_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../helpers.dart';

/// Builds the current schema on [raw], then drops [tables] and sets the version back, to
/// recreate what an older install has on disk.
Future<void> rewindTo(Database raw, int version, List<String> tables) async {
  final current = AppDatabase(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));
  await current.customSelect('SELECT 1').get();
  await current.close();
  for (final table in tables) {
    raw.execute('DROP TABLE $table');
  }
  raw.execute('PRAGMA user_version = $version');
}

Future<void> expectCurrentSchemaWorks(Database raw) async {
  final db = AppDatabase(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));
  addTearDown(db.close);
  await TrackerRepository(db, const Uuid(), () => testNow).add(
    EntryInput(type: GamblingEntryType.deposit, amountCents: 100, occurredAt: testNow, gamblingType: GamblingType.casino),
  );
  await UrgeRepository(db, const Uuid(), () => testNow).start(trigger: TriggerType.stress, minutes: 10);

  expect(await db.select(db.gamblingEntries).get(), hasLength(1));
  expect(await db.select(db.urges).get(), hasLength(1));
  final goalId = await GoalRepository(db, const Uuid(), () => testNow).addGoal(
    const GoalInput(name: 'Car', category: GoalCategory.car, targetCents: 100),
  );
  await GoalRepository(db, const Uuid(), () => testNow).addContribution(goalId, 50, ContributionSource.manual);
  expect(await db.select(db.goalContributions).get(), hasLength(1));
    await ProtectionRepository(db, const Uuid(), () => testNow).startLock(7);
  expect(await db.select(db.protectionLocks).get(), hasLength(1));
  expect(raw.select('PRAGMA user_version').single.values.single, 5);
}

void main() {
  setUp(() => createTestDatabase().close());

  test('version 1 upgrades to the current schema', () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);
    await rewindTo(raw, 1, ['gambling_entries', 'urges', 'goal_contributions', 'recovery_goals', 'protection_removal_requests', 'protection_locks', 'blocked_domains', 'local_settings']);
    await expectCurrentSchemaWorks(raw);
  });

  test('version 2 upgrades to the current schema', () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);
    await rewindTo(raw, 2, ['urges', 'goal_contributions', 'recovery_goals', 'protection_removal_requests', 'protection_locks', 'blocked_domains', 'local_settings']);
    await expectCurrentSchemaWorks(raw);
  });

  test('version 3 upgrades to the current schema', () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);
    await rewindTo(raw, 3, ['goal_contributions', 'recovery_goals', 'protection_removal_requests', 'protection_locks', 'blocked_domains', 'local_settings']);
    await expectCurrentSchemaWorks(raw);
  });

  test('version 4 upgrades to the current schema', () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);
    await rewindTo(raw, 4, ['protection_removal_requests', 'protection_locks', 'blocked_domains', 'local_settings']);
    await expectCurrentSchemaWorks(raw);
  });
}
