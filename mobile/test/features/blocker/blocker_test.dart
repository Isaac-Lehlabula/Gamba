import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/network/api_client.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/core/storage/secure_store.dart';
import 'package:reclaim_app/features/blocker/data/blocker_repositories.dart';
import 'package:reclaim_app/features/blocker/domain/blocker_models.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:uuid/uuid.dart';

import '../../fake_api.dart';
import '../../helpers.dart';

const seed = '''
# comment
betway.co.za SportsBetting
Stake.com Casino

lottostar.co.za Lottery
''';

void main() {
  group('domains', () {
    test('typed sites are normalised, and junk is refused', () {
      expect(normalizeDomain('https://www.Example.com/path?q=1'), 'example.com');
      expect(normalizeDomain(' sub.example.co.za. '), 'sub.example.co.za');
      expect(normalizeDomain('example.com:8080'), 'example.com');
      for (final bad in ['', 'localhost', 'not a site', '-bad.com', 'bad-.com', 'a..com']) {
        expect(normalizeDomain(bad), isNull, reason: bad);
      }
    });

    test('the seed file is parsed, ignoring comments and blank lines', () {
      expect(parseSeedDomains(seed), ['betway.co.za', 'stake.com', 'lottostar.co.za']);
    });

    test("the app's bundled list matches the backend's starter list", () {
      final mobile = parseSeedDomains(File('assets/blocklist-seed.txt').readAsStringSync());
      final backend = parseSeedDomains(File('../backend/src/Reclaim.Infrastructure/Seed/blocklist-seed.txt').readAsStringSync());
      expect(mobile, backend);
      expect(mobile, isNotEmpty);
    });
  });

  group('blocklist', () {
    late AppDatabase db;
    late FakeApi api;
    late BlocklistRepository repo;

    setUp(() {
      db = createTestDatabase();
      api = FakeApi();
      final store = InMemorySecureStore();
      repo = BlocklistRepository(db, fakeDio(api, TokenStore(store)), () async => seed, () => testNow);
    });

    tearDown(() => db.close());

    test('seeds once, then syncs additions and removals from the server', () async {
      await repo.ensureSeeded();
      await repo.ensureSeeded();
      expect(await repo.activeDomains(), ['betway.co.za', 'lottostar.co.za', 'stake.com']);

      await repo.addCustom('my-casino.example');
      api.on('GET /api/v1/blocklist', (r) => (200, {
            'items': [
              {'domain': 'newbet.co.za', 'category': 'SportsBetting', 'isActive': true, 'updatedAtUtc': '2026-10-29T10:00:00Z'},
              {'domain': 'stake.com', 'category': 'Casino', 'isActive': false, 'updatedAtUtc': '2026-10-29T10:00:00Z'},
              {'domain': 'my-casino.example', 'category': 'Casino', 'isActive': false, 'updatedAtUtc': '2026-10-29T10:00:00Z'},
            ],
            'nextSince': '2026-10-29T10:00:00Z',
          }));

      expect(await repo.syncFromServer(), 3);
      expect(await repo.activeDomains(), ['betway.co.za', 'lottostar.co.za', 'my-casino.example', 'newbet.co.za'],
          reason: 'server can deactivate its own domains, but never the user\'s');
      expect(api.requests.single.headers['Authorization'], isNull, reason: 'the blocklist needs no account');

      await repo.syncFromServer();
      expect(api.requests.last.uri.queryParameters['since'], '2026-10-29T10:00:00Z');
    });

    test('custom domains are validated and can be removed', () async {
      expect(await repo.addCustom('nope'), isNull);
      expect(await repo.addCustom('https://www.Example.com/x'), 'example.com');
      expect((await repo.watchCustom().first).map((d) => d.domain), ['example.com']);
      await repo.removeCustom('example.com');
      expect(await repo.watchCustom().first, isEmpty);
    });

    test('a failed sync leaves the list alone', () async {
      await repo.ensureSeeded();
      api.on('GET /api/v1/blocklist', (_) => (500, null));
      await expectLater(repo.syncFromServer(), throwsA(isA<DioException>()));
      expect(await repo.activeDomains(), hasLength(3));
    });
  });

  group('protection lock', () {
    late AppDatabase db;
    late DateTime now;
    late ProtectionRepository repo;

    setUp(() {
      db = createTestDatabase();
      now = testNow;
      repo = ProtectionRepository(db, const Uuid(), () => now);
    });

    tearDown(() => db.close());

    test('ending early takes a request and a 24-hour wait', () async {
      await repo.startLock(30);
      expect(await repo.isLocked(), isTrue);
      expect(() => repo.startLock(7), throwsStateError);

      await repo.requestRemoval();
      now = now.add(const Duration(hours: 23));
      expect(await repo.completeRemoval(), isFalse);
      expect(await repo.isLocked(), isTrue);

      now = now.add(const Duration(hours: 2));
      expect(await repo.completeRemoval(), isTrue);
      expect(await repo.isLocked(), isFalse);
    });

    test('a cancelled request keeps the lock', () async {
      await repo.startLock(7);
      await repo.requestRemoval();
      await repo.cancelRemoval();
      now = now.add(const Duration(days: 2));
      expect(await repo.completeRemoval(), isFalse);
      expect(await repo.isLocked(), isTrue);
    });

    test('a lock ends by itself when its time is up', () async {
      await repo.startLock(1);
      now = now.add(const Duration(days: 1, minutes: 1));
      expect(await repo.isLocked(), isFalse);
      expect(await repo.watchLock().first, isNull);
    });

    test('only the offered lengths are allowed', () {
      expect(() => repo.startLock(3), throwsArgumentError);
    });
  });

  testWidgets('turning protection on, adding a site, and the lock stopping it being turned off', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await ProfileRepository(db, const Uuid(), () => testNow).completeOnboarding(
      const OnboardingAnswers(frequencyBand: FrequencyBand.weekly, goal: RecoveryGoalType.stop),
    );
    final blocker = FakeBlocker();
    await pumpApp(tester, db, blocker: blocker);

    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Protection is off'), findsOneWidget);
    expect(blocker.domains, contains('betway.co.za'), reason: 'the bundled list is ready before any sync');

    await tester.tapOn(find.byType(Switch));
    expect(find.text('Protection is on'), findsOneWidget);
    expect(blocker.running, isTrue);

    await tester.enterText(find.byType(TextField), 'https://my-local-casino.example/play');
    await tester.tapOn(find.byTooltip('Block this site'));
    expect(blocker.domains, contains('my-local-casino.example'));

    await tester.tapButton('Lock protection');
    await tester.tapText('7 days');
    await tester.tapButton('Lock it');
    expect(await tester.reveal(find.textContaining('Locked until')), findsOneWidget);

    await tester.tapOn(find.byType(Switch));
    expect(find.text('Protection is locked. Request to unlock it below.'), findsOneWidget);
    expect(blocker.running, isTrue);

    await tester.tapOn(find.byTooltip('Stop blocking my-local-casino.example'));
    expect(blocker.domains, contains('my-local-casino.example'));

    await tester.disposeApp();
  });

  testWidgets('declining the VPN permission leaves protection off with a kind note', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await ProfileRepository(db, const Uuid(), () => testNow).completeOnboarding(
      const OnboardingAnswers(frequencyBand: FrequencyBand.weekly, goal: RecoveryGoalType.stop),
    );
    await pumpApp(tester, db, blocker: FakeBlocker(grantPermission: false));

    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    await tester.tapOn(find.byType(Switch));
    expect(find.text('Protection is off'), findsOneWidget);
    expect(find.textContaining('needs permission'), findsOneWidget);

    await tester.disposeApp();
  });

  testWidgets('phones without blocking support say so honestly', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await ProfileRepository(db, const Uuid(), () => testNow).completeOnboarding(
      const OnboardingAnswers(frequencyBand: FrequencyBand.weekly, goal: RecoveryGoalType.stop),
    );
    await pumpApp(tester, db, blocker: FakeBlocker(supported: false));
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Not available on this phone yet'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);

    await tester.disposeApp();
  });
}
