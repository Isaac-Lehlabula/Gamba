import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:reclaim_app/features/tracker/domain/money.dart';
import 'package:uuid/uuid.dart';

import '../../helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = createTestDatabase();
    // Started four days ago, usually spends R3 650 a month (R120 a day).
    await ProfileRepository(db, const Uuid(), () => testNow.subtract(const Duration(days: 4))).completeOnboarding(
      const OnboardingAnswers(
        gamblingTypes: {GamblingType.crashGame},
        frequencyBand: FrequencyBand.daily,
        approxMonthlySpendRands: 3650,
        goal: RecoveryGoalType.stop,
      ),
    );
  });

  tearDown(() => db.close());

  Finder fieldLabelled(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextFormField)).first;

  testWidgets('logging, editing and deleting an entry updates the dashboard', (tester) async {
    await pumpApp(tester, db);
    expect(find.text('5 days'), findsOneWidget);
    expect(find.text(formatRands(5 * 12000, whole: true)), findsOneWidget);

    // Log a R250 deposit from Home.
    await tester.tapButton('Log an entry');
    expect(find.text('Add an entry'), findsOneWidget);
    await tester.tapButton('Save');
    expect(find.text('Enter an amount, like 250 or 250.50'), findsOneWidget);

    await tester.enterText(fieldLabelled('Amount'), '250');
    await tester.enterText(fieldLabelled('Where (optional)'), 'Betway');
    await tester.tapButton('Save');

    // Gambling logged today: the run resets, without judgement, and the estimate drops by R250.
    expect(await tester.reveal(find.textContaining("You've logged gambling today")), findsOneWidget);
    expect(await tester.reveal(find.text(formatRands(5 * 12000 - 25000, whole: true))), findsOneWidget);
    expect(find.text(formatRands(25000)), findsWidgets);

    final saved = await db.select(db.gamblingEntries).getSingle();
    expect(saved.gamblingType, GamblingType.crashGame); // defaulted from onboarding
    expect(saved.platformName, 'Betway');

    // Edit it from the Progress list into a withdrawal: no longer gambling, so the run is back.
    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    await tester.tapText('Deposit · ${formatRands(25000)}');
    expect(find.text('Edit entry'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Withdrawal'));
    await tester.pumpAndSettle();
    await tester.tapButton('Save changes');
    expect(find.text('Withdrawal · ${formatRands(25000)}'), findsOneWidget);

    await tester.tapText('Withdrawal · ${formatRands(25000)}');
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tapButton('Delete');
    expect(find.textContaining('Nothing logged yet'), findsOneWidget);
    expect(await db.select(db.gamblingEntries).get(), isEmpty);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(await tester.reveal(find.text('5 days')), findsOneWidget);

    await tester.disposeApp();
  });
}
