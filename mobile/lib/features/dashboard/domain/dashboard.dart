import '../../tracker/domain/money.dart';

/// Gambling-free runs since the journey started. Days are counted by calendar date.
class Streaks {
  const Streaks({required this.current, required this.longest, required this.journeyDay});

  /// Consecutive days up to and including today with no gambling logged. 0 if today has some.
  final int current;
  final int longest;

  /// Day 1 is the day the journey started.
  final int journeyDay;

  static Streaks compute({required DateTime start, required Iterable<DateTime> gamblingDates, required DateTime now}) {
    // UTC calendar dates, so a daylight-saving shift can't make a day 23 hours long.
    DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    final first = day(start);
    final today = day(now);
    if (today.isBefore(first)) return const Streaks(current: 0, longest: 0, journeyDay: 0);

    final gambled = {
      for (final d in gamblingDates.map(day))
        if (!d.isBefore(first) && !d.isAfter(today)) d,
    }.toList()
      ..sort();

    var longest = 0;
    var runStart = first;
    for (final d in gambled) {
      final run = d.difference(runStart).inDays;
      if (run > longest) longest = run;
      runStart = d.add(const Duration(days: 1));
    }
    final current = runStart.isAfter(today) ? 0 : today.difference(runStart).inDays + 1;
    return Streaks(
      current: current,
      longest: current > longest ? current : longest,
      journeyDay: today.difference(first).inDays + 1,
    );
  }
}

/// A supportive estimate, never a fact: what the user said they usually spend over the
/// journey so far, minus what they have actually lost since starting.
int? estimateMoneyKeptCents({
  required int? usualMonthlySpendRands,
  required int journeyDays,
  required int netLossSinceStartCents,
}) {
  if (usualMonthlySpendRands == null || usualMonthlySpendRands <= 0 || journeyDays <= 0) return null;
  final expected = (usualMonthlySpendRands * 100 * 12 * journeyDays / 365).round();
  final spent = netLossSinceStartCents > 0 ? netLossSinceStartCents : 0;
  final kept = expected - spent;
  return kept > 0 ? kept : 0;
}

class DashboardSummary {
  const DashboardSummary({required this.streaks, required this.thisMonth, required this.moneyKeptCents, required this.usualMonthlySpendRands});

  final Streaks streaks;
  final GamblingTotals thisMonth;
  final int? moneyKeptCents;
  final int? usualMonthlySpendRands;

  static DashboardSummary compute({
    required DateTime start,
    required List<({GamblingEntryType type, int amountCents, DateTime occurredAt})> entries,
    required int? usualMonthlySpendRands,
    required DateTime now,
    List<DateTime> otherGamblingDates = const [],
  }) {
    final startDay = DateTime(start.year, start.month, start.day);
    final monthStart = StatsPeriod.month.startFor(now)!;
    final streaks = Streaks.compute(
      start: start,
      gamblingDates: [
        for (final e in entries) if (e.type.isGamblingActivity) e.occurredAt,
        ...otherGamblingDates,
      ],
      now: now,
    );
    final sinceStart = GamblingTotals.of([
      for (final e in entries) if (!e.occurredAt.isBefore(startDay)) (type: e.type, amountCents: e.amountCents),
    ]);

    return DashboardSummary(
      streaks: streaks,
      thisMonth: GamblingTotals.of([
        for (final e in entries) if (!e.occurredAt.isBefore(monthStart)) (type: e.type, amountCents: e.amountCents),
      ]),
      moneyKeptCents: estimateMoneyKeptCents(
        usualMonthlySpendRands: usualMonthlySpendRands,
        journeyDays: streaks.journeyDay,
        netLossSinceStartCents: sinceStart.netLoss,
      ),
      usualMonthlySpendRands: usualMonthlySpendRands,
    );
  }
}
