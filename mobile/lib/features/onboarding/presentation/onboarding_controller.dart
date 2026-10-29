import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/onboarding_models.dart';

part 'onboarding_controller.g.dart';

/// The in-progress answers. Nothing is saved until the last step.
@riverpod
class OnboardingDraft extends _$OnboardingDraft {
  @override
  OnboardingAnswers build() => const OnboardingAnswers();

  void toggleGamblingType(GamblingType type) => state = state.copyWith(gamblingTypes: _toggle(state.gamblingTypes, type));

  void setFrequency(FrequencyBand band) => state = state.copyWith(frequencyBand: band);

  void setMonthlySpend(int? rands) => state = state.copyWith(approxMonthlySpendRands: () => rands);

  void toggleTrigger(TriggerType trigger) => state = state.copyWith(triggers: _toggle(state.triggers, trigger));

  void setGoal(RecoveryGoalType goal) => state = state.copyWith(goal: goal);

  void setMoneyGoal(String? text) => state = state.copyWith(moneyGoalPreference: () => text);

  static Set<T> _toggle<T>(Set<T> set, T value) => set.contains(value) ? ({...set}..remove(value)) : {...set, value};
}
