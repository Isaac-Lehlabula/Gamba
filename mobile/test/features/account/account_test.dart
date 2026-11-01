import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/network/api_client.dart';
import 'package:reclaim_app/core/storage/secure_store.dart';
import 'package:reclaim_app/features/account/data/account_repository.dart';
import 'package:reclaim_app/features/account/data/backup_service.dart';
import 'package:reclaim_app/features/goals/data/goal_repository.dart';
import 'package:reclaim_app/features/goals/domain/goal_models.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:reclaim_app/features/tracker/data/tracker_repository.dart';
import 'package:reclaim_app/features/tracker/domain/money.dart';
import 'package:reclaim_app/features/urges/data/urge_repository.dart';
import 'package:uuid/uuid.dart';

import '../../fake_api.dart';
import '../../helpers.dart';

void main() {
  late InMemorySecureStore store;
  late TokenStore tokens;
  late FakeApi api;
  late Dio dio;

  setUp(() {
    store = InMemorySecureStore();
    tokens = TokenStore(store);
    api = FakeApi();
    dio = fakeDio(api, tokens);
  });

  group('auth interceptor', () {
    test('adds the access token, and refreshes once on a 401 before retrying', () async {
      await tokens.save(const AuthTokens(accessToken: 'old', refreshToken: 'r1', userId: 'u-1'));
      api
        ..on('GET /api/v1/profile', (r) => r.headers['Authorization'] == 'Bearer new' ? (200, {'ok': true}) : (401, null))
        ..on('POST /api/v1/auth/refresh', (r) => (200, tokensJson('new', 'r2')));

      final response = await dio.get<Map<String, dynamic>>('/api/v1/profile');
      expect(response.data, {'ok': true});
      expect(api.sentTo('POST /api/v1/auth/refresh'), hasLength(1));
      expect((await tokens.read())!.refreshToken, 'r2');
    });

    test('a rejected refresh signs the phone out', () async {
      await tokens.save(const AuthTokens(accessToken: 'old', refreshToken: 'stolen', userId: 'u-1'));
      api
        ..on('GET /api/v1/profile', (_) => (401, null))
        ..on('POST /api/v1/auth/refresh', (_) => (401, null));

      await expectLater(
        dio.get<void>('/api/v1/profile'),
        throwsA(isA<DioException>().having((e) => e.error, 'error', isA<SignedOutException>())),
      );
      expect(await tokens.read(), isNull);
    });

    test('requests needing an account fail fast when signed out', () async {
      await expectLater(dio.get<void>('/api/v1/goals'), throwsA(isA<DioException>()));
      expect(api.requests, isEmpty, reason: 'nothing is sent without a token');
    });
  });

  group('account repository', () {
    test('sign-in stores tokens; wrong details give a friendly message', () async {
      final repo = AccountRepository(dio, tokens);
      api.on('POST /api/v1/auth/login', (r) => (r.data as Map)['password'] == 'right password' ? (200, tokensJson('a', 'r')) : (401, null));

      await expectLater(repo.signIn('me@example.com', 'wrong'), throwsA(isA<AccountException>()));
      expect(await repo.isSignedIn(), isFalse);

      await repo.signIn(' Me@Example.com ', 'right password');
      expect(await repo.isSignedIn(), isTrue);
      expect(await repo.signedInEmail(), 'me@example.com');
      expect(api.sentTo('POST /api/v1/auth/login').last.headers['Authorization'], isNull);
    });

    test('sign-out clears tokens even when the server is unreachable', () async {
      await tokens.save(const AuthTokens(accessToken: 'a', refreshToken: 'r', userId: 'u'));
      await AccountRepository(dio, tokens).signOut();
      expect(await tokens.read(), isNull);
    });
  });

  test('backup payload uses the API shapes', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await ProfileRepository(db, const Uuid(), () => testNow).completeOnboarding(
      const OnboardingAnswers(
        gamblingTypes: {GamblingType.crashGame},
        frequencyBand: FrequencyBand.severalTimesAWeek,
        approxMonthlySpendRands: 1500,
        triggers: {TriggerType.tryingToRecoverLosses},
        goal: RecoveryGoalType.stop,
      ),
    );
    await TrackerRepository(db, const Uuid(), () => testNow).add(
      EntryInput(type: GamblingEntryType.deposit, amountCents: 12345, occurredAt: testNow, gamblingType: GamblingType.crashGame),
    );
    await UrgeRepository(db, const Uuid(), () => testNow).start(trigger: TriggerType.payday, minutes: 20);
    final goals = GoalRepository(db, const Uuid(), () => testNow);
    await goals.addContribution(
      await goals.addGoal(const GoalInput(name: 'Car', category: GoalCategory.houseDeposit, targetCents: 2000000)),
      5050,
      ContributionSource.estimatedSavings,
    );

    final payload = await BackupService(db, dio, store, () => testNow).buildPayload();
    final json = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

    final onboarding = (json['onboardingResponses'] as List).single as Map;
    expect(onboarding['frequencyBand'], 'SeveralTimesAWeek');
    expect(onboarding['triggers'], ['TryingToRecoverLosses']);
    expect(onboarding['approxMonthlySpend'], 1500);

    final entry = (json['entries'] as List).single as Map;
    expect((entry['entryType'], entry['amount'], entry['gamblingType']), ('Deposit', 123.45, 'CrashGame'));
    expect((entry['occurredAtUtc'] as String).endsWith('Z'), isTrue);

    final urge = (json['urges'] as List).single as Map;
    expect((urge['trigger'], urge['outcome']), ('Payday', null));

    final goal = (json['goals'] as List).single as Map;
    expect((goal['category'], goal['targetAmount']), ('HouseDeposit', 20000));
    expect(((goal['contributions'] as List).single as Map)['source'], 'EstimatedSavings');
    expect((json['profile'] as Map)['recoveryGoalType'], 'Stop');
  });

  testWidgets('creating an account from Settings backs up straight away', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await ProfileRepository(db, const Uuid(), () => testNow).completeOnboarding(
      const OnboardingAnswers(frequencyBand: FrequencyBand.weekly, goal: RecoveryGoalType.reduce),
    );
    api
      ..on('POST /api/v1/auth/register', (_) => (201, tokensJson('a', 'r')))
      ..on('POST /api/v1/backup', (r) => r.headers['Authorization'] == 'Bearer a' ? (200, {'created': 2, 'updated': 1, 'skipped': 0}) : (401, null));

    await pumpApp(tester, db, apiClient: (store) => fakeDio(api, TokenStore(store)));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tapText('Back up my data');

    await tester.enterText(find.ancestor(of: find.text('Email'), matching: find.byType(TextFormField)), 'me@example.com');
    await tester.enterText(find.ancestor(of: find.text('Choose a password'), matching: find.byType(TextFormField)), 'correct horse');
    // "Create account" is also the label of the mode toggle; tap the submit button.
    await tester.tap(find.ancestor(of: find.text('Create account'), matching: find.byType(FilledButton)));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Your data is backed up.'), findsOneWidget);
    expect(await tester.reveal(find.text('me@example.com')), findsOneWidget);
    final register = api.sentTo('POST /api/v1/auth/register').single.data as Map;
    expect(register['localProfileId'], (await db.select(db.localProfiles).getSingle()).id);
    expect(api.sentTo('POST /api/v1/backup'), hasLength(1));

    await tester.disposeApp();
  });
}
