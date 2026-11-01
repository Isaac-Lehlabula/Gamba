/// Recovery milestones, counted in days without gambling. Presented calmly: no badges,
/// confetti or streak-loss alarms (docs/PRODUCT.md, principle 5).
class Milestone {
  const Milestone(this.days, this.title, this.message);

  final int days;
  final String title;
  final String message;
}

abstract final class Milestones {
  static const all = [
    Milestone(1, 'Day 1', 'You started. That is often the hardest part.'),
    Milestone(3, '3 days', 'Urges can be strong in the first few days. Each one you wait out counts.'),
    Milestone(7, '1 week', 'A full week. Many people find the first week the most difficult.'),
    Milestone(14, '2 weeks', 'Two weeks of choosing something else. Routines start to shift.'),
    Milestone(30, '1 month', 'A month. Look back at what has helped, and keep using it.'),
    Milestone(60, '2 months', 'Two months. Notice what is different now, however small.'),
    Milestone(90, '3 months', 'Three months. A real change, built one day at a time.'),
    Milestone(180, '6 months', 'Half a year. Hard days still come, and you know you can get through them.'),
    Milestone(365, '1 year', 'A year. Whatever today brings, this is yours.'),
  ];

  /// The next milestone after [days], or null once every one is reached.
  static Milestone? next(int days) {
    for (final m in all) {
      if (m.days > days) return m;
    }
    return null;
  }
}
