/// Same members as the backend's goal categories.
enum GoalCategory {
  emergencyFund('Emergency fund'),
  car('Car'),
  houseDeposit('House deposit'),
  debt('Paying off debt'),
  holiday('Holiday'),
  education('Education'),
  family('Family'),
  savings('Savings'),
  custom('Something else');

  const GoalCategory(this.label);
  final String label;
}

/// Same members as the backend's contribution source.
enum ContributionSource {
  /// Money the user says they have actually put aside.
  manual('Set aside'),

  /// Part of the app's estimate of money kept by not gambling. Always shown as an estimate.
  estimatedSavings('From estimated savings');

  const ContributionSource(this.label);
  final String label;
}

const maxGoalNameLength = 60;

class GoalProgress {
  const GoalProgress({required this.targetCents, required this.savedCents});

  final int targetCents;
  final int savedCents;

  double get fraction => targetCents <= 0 ? 0 : (savedCents / targetCents).clamp(0, 1).toDouble();
  int get remainingCents => savedCents >= targetCents ? 0 : targetCents - savedCents;
  bool get isReached => savedCents >= targetCents;

  /// Roughly how much a month is needed to reach the target by [targetDate], counting the
  /// current month. Null when there's no date, it has passed, or the goal is reached.
  int? monthlyNeededCents({required DateTime? targetDate, required DateTime now}) {
    if (targetDate == null || isReached) return null;
    final months = (targetDate.year - now.year) * 12 + targetDate.month - now.month + 1;
    if (months <= 0 || targetDate.isBefore(DateTime(now.year, now.month, now.day))) return null;
    return (remainingCents / months).ceil();
  }
}

/// How much of the money-kept estimate hasn't yet been moved into a goal. If the estimate
/// falls (after logging a loss, say), it can be less than what's already been moved; then
/// nothing is available, and existing contributions stay as they are.
int? availableEstimatedSavingsCents({required int? moneyKeptCents, required int movedToGoalsCents}) {
  if (moneyKeptCents == null) return null;
  final available = moneyKeptCents - movedToGoalsCents;
  return available > 0 ? available : 0;
}
