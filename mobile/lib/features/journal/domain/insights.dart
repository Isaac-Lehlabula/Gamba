import '../../onboarding/domain/onboarding_models.dart';
import 'journal_models.dart';

/// One recorded urge, whether it came from the journal or the "I feel like gambling" flow.
class UrgeEvent {
  const UrgeEvent({required this.at, this.trigger, this.gambled, this.helped = const []});

  final DateTime at;
  final TriggerType? trigger;

  /// Null when the outcome wasn't recorded.
  final bool? gambled;
  final List<CopingStrategy> helped;
}

class Insight {
  const Insight(this.text);
  final String text;

  @override
  String toString() => text;
}

/// Descriptive patterns in what the user recorded. Deliberately plain: they describe the
/// record, never diagnose or predict, and only appear once there's enough data to be fair.
/// Mirrored by the backend's journal insights (Reclaim.Application/Journal); keep in step.
abstract final class Insights {
  static const minimumEvents = 5;

  static const disclaimer = "These are patterns in what you've recorded, not a diagnosis.";

  static List<Insight> describe(List<UrgeEvent> events) {
    if (events.length < minimumEvents) return const [];
    return [
      ?_timeOfDay(events),
      ?_dayOfWeek(events),
      ?_trigger(events),
      ?_whatHelped(events),
    ];
  }

  /// The 3-hour window holding the most urges, if it holds at least 40% of them.
  static Insight? _timeOfDay(List<UrgeEvent> events) {
    final byHour = List.filled(24, 0);
    for (final e in events) {
      byHour[e.at.hour]++;
    }
    var bestStart = 0, bestCount = 0;
    for (var start = 0; start < 24; start++) {
      final count = byHour[start] + byHour[(start + 1) % 24] + byHour[(start + 2) % 24];
      if (count > bestCount) {
        bestStart = start;
        bestCount = count;
      }
    }
    if (bestCount < 3 || bestCount / events.length < 0.4) return null;
    String hh(int h) => '${(h % 24).toString().padLeft(2, '0')}:00';
    final share = bestCount == events.length ? 'All' : '$bestCount of ${events.length}';
    return Insight('$share of your recorded urges happened between ${hh(bestStart)} and ${hh(bestStart + 3)}.');
  }

  static const _days = ['Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays', 'Sundays'];

  /// A weekday holding at least 30% of urges, with at least 7 recorded overall.
  static Insight? _dayOfWeek(List<UrgeEvent> events) {
    if (events.length < 7) return null;
    final byDay = List.filled(7, 0);
    for (final e in events) {
      byDay[e.at.weekday - 1]++;
    }
    final top = _argMax(byDay);
    if (byDay[top] / events.length < 0.3) return null;
    return Insight('Urges came up most often on ${_days[top]} (${byDay[top]} of ${events.length}).');
  }

  /// The most common trigger, if it accounts for at least 30% of urges with one recorded.
  static Insight? _trigger(List<UrgeEvent> events) {
    final counts = <TriggerType, int>{};
    for (final e in events) {
      if (e.trigger case final t? when t != TriggerType.other) counts[t] = (counts[t] ?? 0) + 1;
    }
    final withTrigger = events.where((e) => e.trigger != null).length;
    if (counts.isEmpty || withTrigger < 4) return null;
    final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    if (top.value < 2 || top.value / withTrigger < 0.3) return null;
    return Insight('"${top.key.label}" was the trigger you recorded most (${top.value} of $withTrigger times).');
  }

  /// What was most often part of getting through an urge.
  static Insight? _whatHelped(List<UrgeEvent> events) {
    final counts = <CopingStrategy, int>{};
    for (final e in events.where((e) => e.gambled == false)) {
      for (final h in e.helped.toSet()) {
        if (h != CopingStrategy.other) counts[h] = (counts[h] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    if (top.value < 2) return null;
    return Insight('"${top.key.label}" was part of ${top.value} of the times you got through an urge.');
  }

  static int _argMax(List<int> values) {
    var best = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[best]) best = i;
    }
    return best;
  }
}
