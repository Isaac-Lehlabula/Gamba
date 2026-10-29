// Same members, in the same order, as the backend enums (which serialise in PascalCase; the
// sync layer converts the first letter).

enum GamblingType {
  sportsBetting('Sports betting'),
  casino('Online casino'),
  slots('Slots'),
  crashGame('Crash games (e.g. Aviator)'),
  lottery('Lottery or Lotto'),
  other('Something else');

  const GamblingType(this.label);
  final String label;
}

enum FrequencyBand {
  lessThanMonthly('Less than once a month'),
  monthly('About once a month'),
  weekly('About once a week'),
  severalTimesAWeek('Several times a week'),
  daily('Most days');

  const FrequencyBand(this.label);
  final String label;
}

/// What tends to come before an urge. Shared with the urge flow.
enum TriggerType {
  stress('Stress'),
  boredom('Boredom'),
  payday('Payday'),
  tryingToRecoverLosses('Trying to win back losses'),
  alcohol('Drinking'),
  friendsGambling('Friends gambling'),
  loneliness('Feeling lonely'),
  excitement('Wanting excitement'),
  financialPressure('Money pressure'),
  other('Something else');

  const TriggerType(this.label);
  final String label;
}

enum RecoveryGoalType {
  stop('Stop gambling', 'Take a full break from gambling.'),
  reduce('Cut down', 'Gamble less and keep it within limits you set.');

  const RecoveryGoalType(this.label, this.description);
  final String label;
  final String description;
}

/// The answers collected during onboarding, before they are saved.
class OnboardingAnswers {
  const OnboardingAnswers({
    this.gamblingTypes = const {},
    this.frequencyBand,
    this.approxMonthlySpendRands,
    this.triggers = const {},
    this.goal,
    this.moneyGoalPreference,
  });

  final Set<GamblingType> gamblingTypes;
  final FrequencyBand? frequencyBand;

  /// Whole rands; optional because some people would rather not say yet.
  final int? approxMonthlySpendRands;
  final Set<TriggerType> triggers;
  final RecoveryGoalType? goal;
  final String? moneyGoalPreference;

  bool get isComplete => frequencyBand != null && goal != null;

  OnboardingAnswers copyWith({
    Set<GamblingType>? gamblingTypes,
    FrequencyBand? frequencyBand,
    int? Function()? approxMonthlySpendRands,
    Set<TriggerType>? triggers,
    RecoveryGoalType? goal,
    String? Function()? moneyGoalPreference,
  }) =>
      OnboardingAnswers(
        gamblingTypes: gamblingTypes ?? this.gamblingTypes,
        frequencyBand: frequencyBand ?? this.frequencyBand,
        approxMonthlySpendRands:
            approxMonthlySpendRands != null ? approxMonthlySpendRands() : this.approxMonthlySpendRands,
        triggers: triggers ?? this.triggers,
        goal: goal ?? this.goal,
        moneyGoalPreference: moneyGoalPreference != null ? moneyGoalPreference() : this.moneyGoalPreference,
      );
}
