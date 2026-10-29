import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/features/dashboard/domain/dashboard.dart';
import 'package:reclaim_app/features/tracker/domain/money.dart';

final start = DateTime(2026, 10, 1);
DateTime oct(int day, [int hour = 12]) => DateTime(2026, 10, day, hour);

void main() {
  group('streaks', () {
    test('day one with nothing logged is a one-day run', () {
      final s = Streaks.compute(start: start, gamblingDates: const [], now: oct(1, 9));
      expect((s.current, s.longest, s.journeyDay), (1, 1, 1));
    });

    test('gambling today resets the current run to zero but keeps the longest', () {
      final s = Streaks.compute(start: start, gamblingDates: [oct(10)], now: oct(10, 20));
      expect(s.current, 0);
      expect(s.longest, 9); // 1st to 9th
      expect(s.journeyDay, 10);
    });

    test('the current run counts from the day after the last gambling day', () {
      final s = Streaks.compute(start: start, gamblingDates: [oct(3), oct(3, 22), oct(20)], now: oct(29));
      expect(s.current, 9); // 21st to 29th
      expect(s.longest, 16); // 4th to 19th
    });

    test('history logged from before the journey started does not count', () {
      final s = Streaks.compute(start: start, gamblingDates: [DateTime(2026, 9, 28)], now: oct(5));
      expect((s.current, s.longest), (5, 5));
    });

    test('a start date in the future gives an empty result instead of negative days', () {
      final s = Streaks.compute(start: oct(30), gamblingDates: const [], now: oct(29));
      expect((s.current, s.longest, s.journeyDay), (0, 0, 0));
    });
  });

  group('estimated money kept', () {
    test('is the usual spend over the journey minus actual losses since starting', () {
      // R3 650 a month is R120 a day; 10 days is R1 200 expected; R200 lost leaves R1 000.
      expect(estimateMoneyKeptCents(usualMonthlySpendRands: 3650, journeyDays: 10, netLossSinceStartCents: 20000), 100000);
    });

    test('never goes below zero, and wins do not inflate it', () {
      expect(estimateMoneyKeptCents(usualMonthlySpendRands: 100, journeyDays: 1, netLossSinceStartCents: 99999), 0);
      expect(
        estimateMoneyKeptCents(usualMonthlySpendRands: 3650, journeyDays: 10, netLossSinceStartCents: -50000),
        estimateMoneyKeptCents(usualMonthlySpendRands: 3650, journeyDays: 10, netLossSinceStartCents: 0),
      );
    });

    test('is not shown without a usual spend to base it on', () {
      expect(estimateMoneyKeptCents(usualMonthlySpendRands: null, journeyDays: 10, netLossSinceStartCents: 0), isNull);
      expect(estimateMoneyKeptCents(usualMonthlySpendRands: 0, journeyDays: 10, netLossSinceStartCents: 0), isNull);
    });
  });

  test('summary: withdrawals do not break a run, and month totals exclude earlier months', () {
    final summary = DashboardSummary.compute(
      start: DateTime(2026, 9, 20),
      entries: [
        (type: GamblingEntryType.deposit, amountCents: 50000, occurredAt: DateTime(2026, 9, 25)),
        (type: GamblingEntryType.withdrawal, amountCents: 10000, occurredAt: oct(28)),
        (type: GamblingEntryType.deposit, amountCents: 20000, occurredAt: oct(5)),
      ],
      usualMonthlySpendRands: 3650,
      now: oct(29),
    );

    expect(summary.streaks.current, 24); // 6th to 29th; the withdrawal on the 28th isn't gambling
    expect(summary.thisMonth.deposited, 20000);
    expect(summary.thisMonth.withdrawn, 10000);
    expect(summary.thisMonth.netLoss, 10000);
    // 40 journey days * R120 = R4 800 expected; R600 net lost since the 20th leaves R4 200.
    expect(summary.moneyKeptCents, 420000);
  });
}
