import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:reclaim_app/features/tracker/data/tracker_repository.dart';
import 'package:reclaim_app/features/tracker/domain/money.dart';
import 'package:uuid/uuid.dart';

import '../../helpers.dart';

EntryInput entry({
  GamblingEntryType type = GamblingEntryType.deposit,
  int cents = 25000,
  DateTime? at,
  String? platform,
  String? notes,
}) =>
    EntryInput(
      type: type,
      amountCents: cents,
      occurredAt: at ?? testNow,
      gamblingType: GamblingType.sportsBetting,
      platformName: platform,
      notes: notes,
    );

void main() {
  late AppDatabase db;
  late TrackerRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = TrackerRepository(db, const Uuid(), () => testNow);
  });

  tearDown(() => db.close());

  test('entries are listed newest first and can be edited and deleted', () async {
    final older = await repo.add(entry(at: testNow.subtract(const Duration(days: 2)), platform: ' Betway ', notes: '  '));
    final newer = await repo.add(entry(type: GamblingEntryType.loss, cents: 5050));

    var all = await repo.watchEntries().first;
    expect(all.map((e) => e.id), [newer, older]);
    expect(all.last.platformName, 'Betway');
    expect(all.last.notes, isNull);

    await repo.update(older, entry(type: GamblingEntryType.withdrawal, cents: 100, at: testNow.subtract(const Duration(days: 2))));
    expect((await repo.find(older))!.entryType, GamblingEntryType.withdrawal);
    expect((await repo.find(older))!.platformName, isNull);

    await repo.delete(newer);
    all = await repo.watchEntries().first;
    expect(all.map((e) => e.id), [older]);
  });

  test('future-dated or out-of-range entries are refused', () async {
    expect(() => repo.add(entry(at: testNow.add(const Duration(hours: 1)))), throwsArgumentError);
    expect(() => repo.add(entry(cents: 0)), throwsArgumentError);
    expect(() => repo.add(entry(cents: maxAmountCents + 1)), throwsArgumentError);
    await repo.add(entry(at: testNow.add(const Duration(minutes: 5))));
  });

  test('platform suggestions are most recent first, without case duplicates', () async {
    await repo.add(entry(at: testNow.subtract(const Duration(days: 3)), platform: 'Betway'));
    await repo.add(entry(at: testNow.subtract(const Duration(days: 2)), platform: 'Hollywoodbets'));
    await repo.add(entry(at: testNow.subtract(const Duration(days: 1)), platform: 'betway'));
    await repo.add(entry());

    expect(await repo.watchPlatformNames().first, ['betway', 'Hollywoodbets']);
  });
}
