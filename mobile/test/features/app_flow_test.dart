import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:uuid/uuid.dart';

import '../helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  Future<void> completeOnboarding(WidgetTester tester) async {
    await tester.tapButton("Let's begin");

    expect(find.text('1 of 6'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.ancestor(of: find.text('Continue'), matching: find.byType(FilledButton))).onPressed, isNull);
    await tester.tapText('Sports betting');
    await tester.tapText('Crash games (e.g. Aviator)');
    await tester.tapButton('Continue');

    await tester.tapText('Several times a week');
    await tester.tapButton('Continue');

    await tester.enterText(find.byType(TextFormField), '2500');
    await tester.tapButton('Continue');

    await tester.tapText('Payday');
    await tester.tapButton('Continue');

    await tester.tapText('Stop gambling');
    await tester.tapButton('Continue');

    await tester.enterText(find.byType(TextFormField), 'Car deposit');
    await tester.tapButton('Finish');
  }

  testWidgets('a new user goes through onboarding, skips the self-check and lands on home', (tester) async {
    await pumpApp(tester, db);
    expect(find.text('This is your space.'), findsOneWidget);

    await completeOnboarding(tester);
    expect(find.text('A short self-check'), findsOneWidget);

    await tester.tapButton('Not now');
    expect(find.text('Good evening'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('without gambling'), findsOneWidget);
    expect(find.text('Estimated money kept'), findsOneWidget);
    expect(find.text('Toward: Car deposit'), findsOneWidget);
    expect(await tester.reveal(find.text('Take a two-minute self-check')), findsOneWidget);

    final response = await db.select(db.onboardingResponses).getSingle();
    expect(response.gamblingTypes, [GamblingType.sportsBetting, GamblingType.crashGame]);
    expect(response.approxMonthlySpendRands, 2500);
    expect(response.goal, RecoveryGoalType.stop);

    await tester.disposeApp();
  });

  testWidgets('the self-check after onboarding shows a calm result with next steps', (tester) async {
    await pumpApp(tester, db);
    await completeOnboarding(tester);
    await tester.tapButton('Start');

    for (var i = 0; i < 9; i++) {
      expect(find.text('Question ${i + 1} of 9'), findsOneWidget);
      await tester.tapText('Almost always');
    }

    expect(find.text('High risk'), findsOneWidget);
    expect(find.text('What might help'), findsOneWidget);
    await tester.reveal(find.textContaining('not a medical diagnosis'));
    expect(find.textContaining('not a medical diagnosis'), findsOneWidget);

    await tester.tapButton('Continue');
    expect(await tester.reveal(find.text('Your latest self-check')), findsOneWidget);
    expect(find.textContaining('High risk'), findsOneWidget);

    await tester.disposeApp();
  });

  testWidgets('a returning user goes straight to home and can move between tabs', (tester) async {
    await ProfileRepository(db, const Uuid(), () => testNow.subtract(const Duration(days: 6))).completeOnboarding(
      const OnboardingAnswers(frequencyBand: FrequencyBand.weekly, goal: RecoveryGoalType.reduce),
    );

    await pumpApp(tester, db);
    expect(find.text('7 days'), findsOneWidget);
    expect(find.textContaining('Day 7 of your journey'), findsOneWidget);

    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Protection is off'), findsOneWidget);

    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    await tester.reveal(find.text('Take the self-check'));
    expect(find.text('Take the self-check'), findsOneWidget);

    await tester.disposeApp();
  });

  testWidgets('going back from the first question returns to welcome without saving', (tester) async {
    await pumpApp(tester, db);
    await tester.tapButton("Let's begin");
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('This is your space.'), findsOneWidget);
    expect(await db.select(db.localProfiles).get(), isEmpty);

    await tester.disposeApp();
  });
}
