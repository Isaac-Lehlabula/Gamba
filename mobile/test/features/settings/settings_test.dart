import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/blocker/data/blocker_platform.dart';
import 'package:reclaim_app/features/goals/data/goal_repository.dart';
import 'package:reclaim_app/features/goals/domain/goal_models.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:reclaim_app/features/settings/domain/pin_hasher.dart';
import 'package:reclaim_app/features/tracker/domain/money.dart';
import 'package:reclaim_app/features/urges/data/urge_repository.dart';
import 'package:uuid/uuid.dart';

import '../../helpers.dart';

void main() {
  group('PIN hashing', () {
    test('verifies only the original PIN, with a fresh salt each time', () {
      final hash = PinHasher.hash('2468', iterations: 1000);
      expect(PinHasher.verify('2468', hash), isTrue);
      expect(PinHasher.verify('2469', hash), isFalse);
      expect(PinHasher.hash('2468', iterations: 1000), isNot(hash));
      expect(hash, isNot(contains('2468')));
    });

    test('malformed stored values fail instead of throwing', () {
      for (final bad in ['', 'x', '1000.!!.??', '0.a.b']) {
        expect(PinHasher.verify('1234', bad), isFalse, reason: bad);
      }
    });

    test('PINs are 4 to 8 digits', () {
      expect(PinHasher.isValidPin('1234'), isTrue);
      expect(PinHasher.isValidPin('12345678'), isTrue);
      for (final bad in ['123', '123456789', '12a4', '']) {
        expect(PinHasher.isValidPin(bad), isFalse, reason: bad);
      }
    });
  });

  group('settings', () {
    late AppDatabase db;
    late DateTime now;

    setUp(() async {
      db = createTestDatabase();
      now = testNow;
      await ProfileRepository(db, const Uuid(), () => testNow.subtract(const Duration(days: 9))).completeOnboarding(
        const OnboardingAnswers(frequencyBand: FrequencyBand.weekly, goal: RecoveryGoalType.reduce),
      );
    });

    tearDown(() => db.close());

    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    }

    Future<void> enterPin(WidgetTester tester, String pin) async {
      await tester.enterText(find.byType(TextField), pin);
      await tester.tapButton('Unlock');
    }

    Future<void> leaveAndReturn(WidgetTester tester, Duration away) async {
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      now = now.add(away);
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('turning on app lock, then the app locks after time away', (tester) async {
      await pumpApp(tester, db, clock: () => now);
      await openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'App lock'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '1234');
      await tester.enterText(fields.at(1), '1243');
      await tester.tapButton('Turn on app lock');
      expect(find.text("The PINs don't match"), findsOneWidget);
      await tester.enterText(fields.at(1), '1234');
      await tester.tapButton('Turn on app lock');
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'App lock')).value, isTrue);

      // A short trip away doesn't lock; a longer one does.
      await leaveAndReturn(tester, const Duration(seconds: 10));
      expect(find.text('Settings'), findsOneWidget);
      await leaveAndReturn(tester, const Duration(minutes: 2));
      expect(find.text('Enter your PIN'), findsOneWidget);

      await enterPin(tester, '0000');
      expect(find.text("That PIN didn't match. Try again."), findsOneWidget);
      await enterPin(tester, '1234');
      expect(find.text('Enter your PIN'), findsNothing);
      expect(find.text('Good evening'), findsOneWidget, reason: 'unlocking returns to Home');

      await tester.disposeApp();
    });

    testWidgets('a locked app opens on the lock screen, and too many wrong PINs pause attempts', (tester) async {
      await testLockRepository().enable('5555', biometrics: false);
      await pumpApp(tester, db, clock: () => now, keepSecureStorage: true);
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.text('Good evening'), findsNothing);

      for (var i = 0; i < 4; i++) {
        await enterPin(tester, '1111');
      }
      await enterPin(tester, '1111');
      expect(find.textContaining('Too many tries'), findsOneWidget);
      await enterPin(tester, '5555');
      expect(find.textContaining('Too many tries'), findsOneWidget, reason: 'even the right PIN waits out the pause');

      now = now.add(const Duration(seconds: 31));
      await enterPin(tester, '5555');
      expect(find.text('Good evening'), findsOneWidget);

      await tester.disposeApp();
    });

    testWidgets('changing the usual spend brings in the money-kept estimate', (tester) async {
      await pumpApp(tester, db);
      expect(find.text('Estimated money kept'), findsNothing);

      await openSettings(tester);
      await tester.tapText('Usual monthly spend');
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), '3650');
      await tester.tapButton('Save');
      expect(find.text(formatRands(365000, whole: true)), findsOneWidget);

      await tester.tapText('What you are aiming for');
      await tester.tapText('Stop gambling');
      expect(find.text('Stop gambling'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(await tester.reveal(find.text('Estimated money kept')), findsOneWidget);
      expect(find.text(formatRands(10 * 12000, whole: true)), findsOneWidget);

      await tester.disposeApp();
    });

    testWidgets('deleting everything empties the database and returns to welcome', (tester) async {
      await UrgeRepository(db, const Uuid(), () => testNow).start(trigger: TriggerType.stress, minutes: 10);
      final goals = GoalRepository(db, const Uuid(), () => testNow);
      await goals.addContribution(
        await goals.addGoal(const GoalInput(name: 'Car', category: GoalCategory.car, targetCents: 100)),
        50,
        ContributionSource.manual,
      );

      final blocker = FakeBlocker()
        ..running = true
        ..log.add(BlockedAttempt(testNow, 'stake.com'));
      await pumpApp(tester, db, blocker: blocker);
      await openSettings(tester);
      await tester.tapText('Delete everything on this phone');
      expect(find.text('This cannot be undone.', findRichText: true), findsNothing);
      await tester.tapButton('Delete everything');

      expect(find.text('This is your space.'), findsOneWidget);
      expect(blocker.running, isFalse);
      expect(blocker.log, isEmpty);
      for (final table in db.allTables) {
        expect(await db.select(table).get(), isEmpty, reason: table.actualTableName);
      }

      await tester.disposeApp();
    });
  });
}
