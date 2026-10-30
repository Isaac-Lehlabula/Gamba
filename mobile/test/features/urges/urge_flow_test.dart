import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:reclaim_app/features/urges/domain/urge_models.dart';
import 'package:uuid/uuid.dart';

import '../../helpers.dart';

void main() {
  late AppDatabase db;
  late DateTime now;

  setUp(() async {
    db = createTestDatabase();
    now = testNow;
    await ProfileRepository(db, const Uuid(), () => testNow.subtract(const Duration(days: 4))).completeOnboarding(
      const OnboardingAnswers(
        frequencyBand: FrequencyBand.weekly,
        triggers: {TriggerType.payday},
        goal: RecoveryGoalType.stop,
        moneyGoalPreference: 'Car deposit',
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> startPause(WidgetTester tester, {required String trigger, required int minutes}) async {
    await tester.tapButton('I feel like gambling');
    expect(find.text(UrgeGuidance.opening), findsOneWidget);
    await tester.tapText(trigger);
    await tester.tapText('$minutes min');
    await tester.tapButton('Start the pause');
  }

  testWidgets('an urge that passes during the pause', (tester) async {
    await pumpApp(tester, db, clock: () => now);
    await startPause(tester, trigger: 'Payday', minutes: 10);

    expect(find.text('10:00'), findsOneWidget);
    expect(await tester.reveal(find.text('Remember why')), findsOneWidget);
    expect(find.text("You've had 5 days without gambling."), findsOneWidget);
    expect(find.text("You're working toward: Car deposit."), findsOneWidget);
    expect(await tester.reveal(find.text(UrgeGuidance.tipsFor(TriggerType.payday).first)), findsOneWidget);

    await tester.tapButton("I'm feeling better now");
    expect(find.text(UrgeGuidance.passed), findsOneWidget);
    await tester.tapButton('Back to home');

    expect(find.text('I feel like gambling'), findsOneWidget);
    expect(find.text('5 days'), findsOneWidget);
    final urge = await db.select(db.urges).getSingle();
    expect((urge.trigger, urge.outcome, urge.coolingOffMinutes), (TriggerType.payday, UrgeOutcome.passed, 10));

    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    expect(await tester.reveal(find.textContaining('1 urge, 1 you rode out')), findsOneWidget);

    await tester.disposeApp();
  });

  testWidgets('when the pause ends: more time, then gambling is logged without judgement', (tester) async {
    await pumpApp(tester, db, clock: () => now);
    await startPause(tester, trigger: 'Boredom', minutes: 10);

    now = now.add(const Duration(minutes: 11));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('The pause is over. How are you feeling now?'), findsOneWidget);

    await tester.tapButton('I need 10 more minutes');
    expect(find.text('09:00'), findsOneWidget);

    now = now.add(const Duration(minutes: 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.tapButton('I gambled');
    expect(find.text(UrgeGuidance.gambled), findsOneWidget);

    await tester.tapButton('Log what you spent');
    expect(find.text('Add an entry'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Even without an amount logged, the urge's outcome counts as a gambling day.
    expect(await tester.reveal(find.textContaining("You've logged gambling today")), findsOneWidget);
    expect((await db.select(db.urges).getSingle()).coolingOffMinutes, 20);

    await tester.disposeApp();
  });

  testWidgets('leaving mid-pause keeps it running and Home offers a way back', (tester) async {
    await pumpApp(tester, db, clock: () => now);
    await startPause(tester, trigger: 'Stress', minutes: 20);

    now = now.add(const Duration(minutes: 5));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Your pause is still going'), findsOneWidget);
    expect(find.text('I feel like gambling'), findsNothing);

    await tester.tapText('Your pause is still going');
    expect(find.text('15:00'), findsOneWidget);

    await tester.disposeApp();
  });
}
