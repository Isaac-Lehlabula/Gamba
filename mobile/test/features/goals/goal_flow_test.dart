import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/goals/domain/goal_models.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:reclaim_app/features/tracker/domain/money.dart';
import 'package:uuid/uuid.dart';

import '../../helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = createTestDatabase();
    // Ten days in at R3 650 a month (R120 a day): R1 200 estimated savings.
    await ProfileRepository(db, const Uuid(), () => testNow.subtract(const Duration(days: 9))).completeOnboarding(
      const OnboardingAnswers(
        frequencyBand: FrequencyBand.daily,
        approxMonthlySpendRands: 3650,
        goal: RecoveryGoalType.stop,
        moneyGoalPreference: 'Car deposit',
      ),
    );
  });

  tearDown(() => db.close());

  Finder field(String label) => find.ancestor(of: find.text(label), matching: find.byType(TextFormField)).first;

  Future<void> enterAmountAndAdd(WidgetTester tester, String amount) async {
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), amount);
    await tester.tapButton('Add');
  }

  testWidgets('the onboarding money goal becomes a goal that savings count toward', (tester) async {
    await pumpApp(tester, db);

    await tester.tapText('Working toward: Car deposit');
    await tester.tapButton('Make "Car deposit" a goal');
    expect(tester.widget<TextFormField>(field('What are you saving for?')).controller!.text, 'Car deposit');

    await tester.tapText('Car');
    await tester.enterText(field('Target amount'), '20000');
    await tester.tapButton('Create goal');

    // Detail screen for the new goal.
    expect(find.text('${formatRands(0, whole: true)} of ${formatRands(2000000, whole: true)}'), findsOneWidget);

    await tester.tapButton('Add money I have set aside');
    await enterAmountAndAdd(tester, '500');
    expect(find.text('${formatRands(50000, whole: true)} of ${formatRands(2000000, whole: true)}'), findsOneWidget);

    // Estimated savings can be counted, but no more than what's available.
    await tester.tapButton('Count estimated savings (${formatRands(120000, whole: true)} available)');
    expect(find.textContaining('not money in a bank account'), findsOneWidget);
    await enterAmountAndAdd(tester, '5000');
    expect(find.text('At most ${formatRands(120000)}'), findsOneWidget);
    await enterAmountAndAdd(tester, '1200');
    expect(await tester.reveal(find.text('No estimated savings left to count')), findsOneWidget);
    expect(find.text('${formatRands(170000, whole: true)} of ${formatRands(2000000, whole: true)}'), findsOneWidget);

    final contributions = await db.select(db.goalContributions).get();
    expect(contributions.map((c) => c.source).toSet(), {ContributionSource.manual, ContributionSource.estimatedSavings});

    // Removing one updates the total.
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    await tester.tapButton('Remove');
    expect(await db.select(db.goalContributions).get(), hasLength(1));

    // Home now shows the goal's progress instead of the prompt.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(await tester.reveal(find.text('Car deposit')), findsOneWidget);
    expect(find.text('Working toward: Car deposit'), findsNothing);

    await tester.disposeApp();
  });

  testWidgets('a goal can be edited and deleted', (tester) async {
    await pumpApp(tester, db);
    await tester.tapText('Working toward: Car deposit');
    await tester.tapButton('Add a different goal');
    await tester.enterText(field('What are you saving for?'), 'School fees');
    await tester.enterText(field('Target amount'), '8000');
    await tester.tapButton('Create goal');

    await tester.tap(find.byTooltip('Edit goal'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Target amount'), '9000');
    await tester.tapButton('Save changes');
    expect(find.text('${formatRands(0, whole: true)} of ${formatRands(900000, whole: true)}'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tapButton('Delete');

    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('School fees'), findsNothing);
    expect(await db.select(db.recoveryGoals).get(), isEmpty);

    await tester.disposeApp();
  });
}
