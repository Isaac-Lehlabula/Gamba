import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:reclaim_app/features/urges/data/urge_repository.dart';
import 'package:reclaim_app/features/urges/domain/urge_models.dart';
import 'package:uuid/uuid.dart';

import '../../helpers.dart';

void main() {
  group('pause timing', () {
    final start = DateTime(2026, 10, 29, 20);

    test('counts down from the stored start time and stops at zero', () {
      expect(UrgePause.remaining(startedAt: start, minutes: 10, now: start), const Duration(minutes: 10));
      expect(UrgePause.remaining(startedAt: start, minutes: 10, now: start.add(const Duration(minutes: 4))), const Duration(minutes: 6));
      expect(UrgePause.remaining(startedAt: start, minutes: 10, now: start.add(const Duration(hours: 1))), Duration.zero);
    });

    test('formats as minutes and seconds, rounding up', () {
      expect(UrgePause.format(const Duration(minutes: 10)), '10:00');
      expect(UrgePause.format(const Duration(minutes: 9, seconds: 5)), '09:05');
      expect(UrgePause.format(const Duration(milliseconds: 400)), '00:01');
      expect(UrgePause.format(Duration.zero), '00:00');
    });
  });

  test('every trigger has guidance, and none of it shames', () {
    final all = [
      UrgeGuidance.opening,
      UrgeGuidance.breathing,
      UrgeGuidance.passed,
      UrgeGuidance.gambled,
      ...UrgeGuidance.grounding,
      for (final t in TriggerType.values) ...UrgeGuidance.tipsFor(t),
    ];
    for (final t in TriggerType.values) {
      expect(UrgeGuidance.tipsFor(t), isNotEmpty, reason: t.name);
    }
    for (final text in all.map((s) => s.toLowerCase())) {
      for (final word in ['addict', 'fail', 'weak', 'should have', 'jackpot']) {
        expect(text, isNot(contains(word)), reason: text);
      }
    }
  });

  group('repository', () {
    late AppDatabase db;
    late DateTime now;
    late UrgeRepository repo;

    setUp(() {
      db = createTestDatabase();
      now = testNow;
      repo = UrgeRepository(db, const Uuid(), () => now);
    });

    tearDown(() => db.close());

    test('a pause can be extended and then resolved once', () async {
      final id = await repo.start(trigger: TriggerType.payday, intensity: 4, minutes: 20);
      expect((await repo.watchActive().first)!.id, id);

      await repo.extend(id);
      expect((await repo.watch(id).first)!.coolingOffMinutes, 30);

      now = now.add(const Duration(minutes: 31));
      await repo.resolve(id, UrgeOutcome.passed);
      await repo.resolve(id, UrgeOutcome.gambled); // already resolved: ignored
      await repo.extend(id); // already resolved: ignored

      final urge = (await repo.watch(id).first)!;
      expect(urge.outcome, UrgeOutcome.passed);
      expect(urge.resolvedAt, now);
      expect(urge.coolingOffMinutes, 30);
      expect(await repo.watchActive().first, isNull);
    });

    test('starting a new urge abandons one left open', () async {
      final first = await repo.start(trigger: TriggerType.stress, minutes: 10);
      now = now.add(const Duration(hours: 1));
      final second = await repo.start(trigger: TriggerType.boredom, minutes: 10);

      expect((await repo.watch(first).first)!.outcome, UrgeOutcome.abandoned);
      expect((await repo.watchActive().first)!.id, second);
      expect((await repo.watchHistory().first).map((u) => u.id), [second, first]);
    });

    test('an open urge from long ago is not treated as in progress', () async {
      await repo.start(trigger: TriggerType.stress, minutes: 10);
      now = now.add(const Duration(hours: 13));
      expect(await UrgeRepository(db, const Uuid(), () => now).watchActive().first, isNull);
    });

    test('only the offered pause lengths and intensities 1 to 5 are accepted', () {
      expect(() => repo.start(trigger: TriggerType.stress, minutes: 7), throwsArgumentError);
      expect(() => repo.start(trigger: TriggerType.stress, minutes: 10, intensity: 6), throwsArgumentError);
    });
  });
}
