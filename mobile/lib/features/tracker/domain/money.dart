import 'package:intl/intl.dart';

/// Same members as the backend's GamblingEntryType.
enum GamblingEntryType {
  deposit('Deposit', 'Money put into a gambling account'),
  withdrawal('Withdrawal', 'Money taken back out'),
  loss('Loss', 'Money lost on a bet or game'),
  win('Win', 'Money won on a bet or game');

  const GamblingEntryType(this.label, this.description);
  final String label;
  final String description;

  /// Whether an entry of this type means gambling happened that day. A withdrawal alone
  /// doesn't: it can be taking money back out to stop.
  bool get isGamblingActivity => this != withdrawal;
}

/// Matches the backend's limit, so anything accepted here also syncs.
const maxAmountCents = 1000000000;

final _rands = NumberFormat.currency(locale: 'en_ZA', symbol: 'R ', decimalDigits: 2);
final _wholeRands = NumberFormat.currency(locale: 'en_ZA', symbol: 'R ', decimalDigits: 0);

/// "R 1 234,50" — South African formatting. [whole] drops the cents for estimates.
String formatRands(int cents, {bool whole = false}) =>
    whole ? _wholeRands.format((cents / 100).round()) : _rands.format(cents / 100);

final _amountPattern = RegExp(r'^\d{1,8}([.,]\d{1,2})?$');

/// Parses what someone types ("250", "250.5", "1 250,50") into cents. Null if not a valid
/// positive amount within the limit.
int? parseRandsToCents(String input) {
  final text = input.replaceAll(RegExp(r'\s'), '');
  if (!_amountPattern.hasMatch(text)) return null;
  final parts = text.replaceAll(',', '.').split('.');
  final rands = int.parse(parts[0]);
  final cents = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  final total = rands * 100 + cents;
  return total > 0 && total <= maxAmountCents ? total : null;
}

/// Totals for a set of entries, in cents.
class GamblingTotals {
  const GamblingTotals({this.deposited = 0, this.withdrawn = 0, this.won = 0, this.lost = 0});

  final int deposited;
  final int withdrawn;
  final int won;
  final int lost;

  /// Same formula as the backend: money moved plus outcomes. People usually log one style;
  /// logging both for the same money counts it twice. Negative means ahead.
  int get netLoss => deposited - withdrawn + lost - won;

  bool get isEmpty => deposited == 0 && withdrawn == 0 && won == 0 && lost == 0;

  static GamblingTotals of(Iterable<({GamblingEntryType type, int amountCents})> entries) {
    var deposited = 0, withdrawn = 0, won = 0, lost = 0;
    for (final e in entries) {
      switch (e.type) {
        case GamblingEntryType.deposit:
          deposited += e.amountCents;
        case GamblingEntryType.withdrawal:
          withdrawn += e.amountCents;
        case GamblingEntryType.win:
          won += e.amountCents;
        case GamblingEntryType.loss:
          lost += e.amountCents;
      }
    }
    return GamblingTotals(deposited: deposited, withdrawn: withdrawn, won: won, lost: lost);
  }
}

enum StatsPeriod {
  today('Today'),
  week('This week'),
  month('This month'),
  all('All time');

  const StatsPeriod(this.label);
  final String label;

  /// Start of the period in local time (weeks start on Monday), or null for all time.
  DateTime? startFor(DateTime now) {
    final midnight = DateTime(now.year, now.month, now.day);
    return switch (this) {
      today => midnight,
      // Built from calendar fields, not by subtracting a Duration, so DST can't shift it to 23:00.
      week => DateTime(now.year, now.month, now.day - (now.weekday - DateTime.monday)),
      month => DateTime(now.year, now.month),
      all => null,
    };
  }
}
