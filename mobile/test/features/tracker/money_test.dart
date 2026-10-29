import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/features/tracker/domain/money.dart';

void main() {
  group('parseRandsToCents', () {
    test('accepts whole rands, cents with either separator, and spaces', () {
      expect(parseRandsToCents('250'), 25000);
      expect(parseRandsToCents('250.5'), 25050);
      expect(parseRandsToCents('250,05'), 25005);
      expect(parseRandsToCents(' 1 250,50 '), 125050);
    });

    test('rejects zero, negatives, too many decimals, junk and amounts over the limit', () {
      for (final bad in ['', '0', '0.00', '-5', '1.234', 'R250', '12a', '10000000.01', '123456789']) {
        expect(parseRandsToCents(bad), isNull, reason: bad);
      }
      expect(parseRandsToCents('10000000'), maxAmountCents);
    });
  });

  test('formatRands uses South African formatting', () {
    final text = formatRands(125050);
    expect(text, startsWith('R '));
    expect(text, endsWith(',50'));
    expect(formatRands(125050, whole: true), isNot(contains(',')));
  });

  test('net loss combines money moved and outcomes, like the backend', () {
    final totals = GamblingTotals.of([
      (type: GamblingEntryType.deposit, amountCents: 50000),
      (type: GamblingEntryType.withdrawal, amountCents: 15000),
      (type: GamblingEntryType.loss, amountCents: 8000),
      (type: GamblingEntryType.win, amountCents: 3000),
    ]);
    expect(totals.netLoss, 40000);
    expect(const GamblingTotals().isEmpty, isTrue);
  });

  test('periods start at local midnight, weeks on Monday', () {
    final thursday = DateTime(2026, 10, 29, 19, 30);
    expect(StatsPeriod.today.startFor(thursday), DateTime(2026, 10, 29));
    expect(StatsPeriod.week.startFor(thursday), DateTime(2026, 10, 26));
    expect(StatsPeriod.month.startFor(thursday), DateTime(2026, 10));
    expect(StatsPeriod.all.startFor(thursday), isNull);
    // A Monday is the start of its own week; a Sunday belongs to the week before.
    expect(StatsPeriod.week.startFor(DateTime(2026, 10, 26, 8)), DateTime(2026, 10, 26));
    expect(StatsPeriod.week.startFor(DateTime(2026, 11, 1, 8)), DateTime(2026, 10, 26));
  });
}
