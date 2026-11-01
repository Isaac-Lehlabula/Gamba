import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/journal/data/journal_repository.dart';
import 'package:reclaim_app/features/journal/domain/insights.dart';
import 'package:reclaim_app/features/journal/domain/journal_models.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:reclaim_app/features/timeline/domain/milestones.dart';
import 'package:reclaim_app/features/urges/data/urge_repository.dart';
import 'package:reclaim_app/features/urges/domain/urge_models.dart';
import 'package:uuid/uuid.dart';

import '../../helpers.dart';

/// Thursday 29 October 2026 at [hour]:00, [daysAgo] days earlier.
DateTime at(int hour, {int daysAgo = 0}) => DateTime(2026, 10, 29 - daysAgo, hour);

UrgeEvent urge(DateTime when, {TriggerType? trigger, bool? gambled, List<CopingStrategy> helped = const []}) =>
    UrgeEvent(at: when, trigger: trigger, gambled: gambled, helped: helped);

void main() {
  group('insights', () {
    test('nothing is said until there are enough urges to be fair', () {
      expect(Insights.describe([for (var i = 0; i < 4; i++) urge(at(21, daysAgo: i), trigger: TriggerType.payday)]), isEmpty);
    });

    test('a clustered time of day is described with the actual counts', () {
      final events = [
        urge(at(20, daysAgo: 1)),
        urge(at(21, daysAgo: 2)),
        urge(at(22, daysAgo: 3)),
        urge(at(21, daysAgo: 4)),
        urge(at(9, daysAgo: 5)),
      ];
      expect(Insights.describe(events).map((i) => i.text), contains('4 of 5 of your recorded urges happened between 20:00 and 23:00.'));
    });

    test('the window can wrap past midnight', () {
      final events = [for (var i = 0; i < 5; i++) urge(at(i.isEven ? 23 : 0, daysAgo: i))];
      expect(Insights.describe(events).first.text, contains('between 22:00 and 01:00'));
    });

    test('spread-out urges produce no time-of-day claim', () {
      final events = [for (final h in [2, 7, 11, 15, 19, 23]) urge(at(h))];
      expect(Insights.describe(events).where((i) => i.text.contains('between')), isEmpty);
    });

    test('weekday, trigger and what helped need enough of a lead to be mentioned', () {
      final fridays = [for (var w = 0; w < 4; w++) DateTime(2026, 10, 2 + 7 * w, 12)];
      final events = [
        for (final f in fridays) urge(f, trigger: TriggerType.payday, gambled: false, helped: [CopingStrategy.walked]),
        urge(DateTime(2026, 10, 5, 8), trigger: TriggerType.boredom, gambled: true),
        urge(DateTime(2026, 10, 6, 15), trigger: TriggerType.stress, gambled: false, helped: [CopingStrategy.breathing]),
        urge(DateTime(2026, 10, 7, 18)),
      ];
      final texts = Insights.describe(events).map((i) => i.text).toList();
      expect(texts, contains('Urges came up most often on Fridays (4 of 7).'));
      expect(texts, contains('"Payday" was the trigger you recorded most (4 of 6 times).'));
      expect(texts, contains('"Went for a walk or moved" was part of 4 of the times you got through an urge.'));
    });

    test('insight wording never diagnoses or shames', () {
      final events = [
        for (var i = 0; i < 8; i++)
          urge(at(21, daysAgo: i * 7), trigger: TriggerType.payday, gambled: i.isOdd, helped: [CopingStrategy.talkedToSomeone]),
      ];
      for (final text in [...Insights.describe(events).map((i) => i.text), Insights.disclaimer]) {
        for (final word in ['addict', 'disorder', 'fail', 'should', 'always']) {
          expect(text.toLowerCase(), isNot(contains(word)), reason: text);
        }
      }
    });
  });

  test('milestones step through to a year', () {
    expect(Milestones.all.first.days, 1);
    expect(Milestones.all.last.days, 365);
    expect(Milestones.next(0)!.days, 1);
    expect(Milestones.next(7)!.days, 14);
    expect(Milestones.next(365), isNull);
  });

  group('journal repository', () {
    late AppDatabase db;
    late JournalRepository repo;

    setUp(() {
      db = createTestDatabase();
      repo = JournalRepository(db, const Uuid(), () => testNow);
    });

    tearDown(() => db.close());

    test('entries are stored, edited and deleted', () async {
      final id = await repo.add(JournalInput(
        occurredAt: at(18),
        mood: 2,
        trigger: TriggerType.payday,
        urgeIntensity: 4,
        outcome: JournalOutcome.resisted,
        helped: {CopingStrategy.leftPhone, CopingStrategy.walked},
        note: '  Payday again  ',
      ));
      var entry = (await repo.find(id))!;
      expect(entry.helped, [CopingStrategy.walked, CopingStrategy.leftPhone]);
      expect(entry.note, 'Payday again');

      await repo.update(id, JournalInput(occurredAt: at(18), mood: 4, note: ' '));
      entry = (await repo.find(id))!;
      expect((entry.mood, entry.trigger, entry.note), (4, null, null));

      await repo.delete(id);
      expect(await repo.watchEntries().first, isEmpty);
    });

    test('empty, out-of-range or future entries are refused', () {
      expect(() => repo.add(JournalInput(occurredAt: at(10))), throwsArgumentError);
      expect(() => repo.add(JournalInput(occurredAt: at(10), mood: 6)), throwsArgumentError);
      expect(() => repo.add(JournalInput(occurredAt: testNow.add(const Duration(hours: 1)), mood: 3)), throwsArgumentError);
    });
  });

  group('screens', () {
    late AppDatabase db;

    setUp(() async {
      db = createTestDatabase();
      await ProfileRepository(db, const Uuid(), () => testNow.subtract(const Duration(days: 8))).completeOnboarding(
        const OnboardingAnswers(frequencyBand: FrequencyBand.weekly, goal: RecoveryGoalType.stop),
      );
    });

    tearDown(() => db.close());

    testWidgets('writing an entry, and patterns appearing once there is enough', (tester) async {
      // Four evening urges from the "I feel like gambling" flow already on record.
      for (var i = 1; i <= 4; i++) {
        final urges = UrgeRepository(db, const Uuid(), () => at(21, daysAgo: i));
        await urges.resolve(await urges.start(trigger: TriggerType.boredom, minutes: 10), UrgeOutcome.passed);
      }
      await pumpApp(tester, db);
      await tester.tap(find.text('Journal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('(1 more)'), findsOneWidget);

      await tester.tapButton('Write an entry');
      await tester.tapButton('Save');
      expect(find.text('Add how you feel, an urge, or a note first.'), findsOneWidget);

      expect(find.text('How strong was it?'), findsNothing, reason: 'urge questions wait until there was an urge');
      await tester.tapOn(find.widgetWithText(ChoiceChip, '2'));
      await tester.tapOn(find.widgetWithText(ChoiceChip, 'Got through it'));
      expect(await tester.reveal(find.text('How strong was it?')), findsOneWidget);
      await tester.tapOn(find.widgetWithText(FilterChip, 'Talked to someone'));
      await tester.enterText(find.byType(TextField), 'Rang my brother instead');
      await tester.tapButton('Save');

      expect(find.textContaining('Mood: Low'), findsOneWidget);
      expect(find.textContaining('Rang my brother instead'), findsOneWidget);
      // The new entry (19:30) joins four 21:00 urges: five in all, every one in the same window.
      expect(find.text('All of your recorded urges happened between 19:00 and 22:00.'), findsOneWidget);
      expect(find.text(Insights.disclaimer), findsOneWidget);

      await tester.disposeApp();
    });

    testWidgets('the Home card opens the timeline', (tester) async {
      await pumpApp(tester, db);
      await tester.tapText('9 days');
      expect(find.text('Your timeline'), findsOneWidget);
      expect(find.textContaining('9 days without gambling. 5 more to 2 weeks.'), findsOneWidget);
      expect(find.bySemanticsLabel('1 week, reached'), findsOneWidget);
      expect(find.bySemanticsLabel('2 weeks, not yet'), findsOneWidget);

      await tester.disposeApp();
    });
  });
}
