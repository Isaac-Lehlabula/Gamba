import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/choice_tile.dart';
import '../data/profile_repository.dart';
import '../domain/onboarding_models.dart';
import 'onboarding_controller.dart';

/// Six short questions, one per page. Optional questions can be skipped.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 6;

  int _step = 0;
  bool _saving = false;

  bool _canContinue(OnboardingAnswers a) => switch (_step) {
        0 => a.gamblingTypes.isNotEmpty,
        1 => a.frequencyBand != null,
        4 => a.goal != null,
        _ => true,
      };

  bool get _isOptional => _step == 2 || _step == 3 || _step == 5;

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_step < _stepCount - 1) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).completeOnboarding(ref.read(onboardingDraftProvider));
      if (mounted) context.go('${Routes.assessment}?next=home');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That didn't save. Please try again.")),
      );
    }
  }

  void _skip() {
    final draft = ref.read(onboardingDraftProvider.notifier);
    if (_step == 2) draft.setMonthlySpend(null);
    if (_step == 5) draft.setMoneyGoal(null);
    _next();
  }

  void _back() {
    if (_step == 0) {
      context.go(Routes.welcome);
    } else {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answers = ref.watch(onboardingDraftProvider);
    final isLast = _step == _stepCount - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: _saving ? null : _back),
          title: Text('${_step + 1} of $_stepCount'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: (_step + 1) / _stepCount),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  key: ValueKey(_step),
                  padding: AppSpacing.screen,
                  children: _stepContent(answers),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                child: Column(
                  children: [
                    FilledButton(
                      onPressed: _canContinue(answers) && !_saving ? _next : null,
                      child: _saving
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(isLast ? 'Finish' : 'Continue'),
                    ),
                    if (_isOptional)
                      TextButton(onPressed: _saving ? null : _skip, child: const Text('Skip this one')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stepContent(OnboardingAnswers a) {
    final draft = ref.read(onboardingDraftProvider.notifier);
    return switch (_step) {
      0 => [
          const _Question('What kinds of gambling have you been doing?', 'Choose any that apply.'),
          for (final type in GamblingType.values)
            ChoiceTile(
              label: type.label,
              multiSelect: true,
              selected: a.gamblingTypes.contains(type),
              onTap: () => draft.toggleGamblingType(type),
            ),
        ],
      1 => [
          const _Question('How often do you usually gamble?', 'Think about the last few months.'),
          for (final band in FrequencyBand.values)
            ChoiceTile(label: band.label, selected: a.frequencyBand == band, onTap: () => draft.setFrequency(band)),
        ],
      2 => [
          const _Question(
            'Roughly how much goes to gambling in a month?',
            'An estimate is fine. It helps show how much money you keep along the way.',
          ),
          _SpendField(initial: a.approxMonthlySpendRands, onChanged: draft.setMonthlySpend),
        ],
      3 => [
          const _Question('What tends to come before an urge?', "Choose any that apply. It's okay if you're not sure yet."),
          for (final trigger in TriggerType.values)
            ChoiceTile(
              label: trigger.label,
              multiSelect: true,
              selected: a.triggers.contains(trigger),
              onTap: () => draft.toggleTrigger(trigger),
            ),
        ],
      4 => [
          const _Question('What would you like to aim for?', 'You can change this at any time.'),
          for (final goal in RecoveryGoalType.values)
            ChoiceTile(
              label: goal.label,
              description: goal.description,
              selected: a.goal == goal,
              onTap: () => draft.setGoal(goal),
            ),
        ],
      _ => [
          const _Question(
            'What would you rather put that money toward?',
            'Something that matters to you. You can add proper goals later.',
          ),
          _MoneyGoalField(initial: a.moneyGoalPreference, onChanged: draft.setMoneyGoal),
        ],
    };
  }
}

class _Question extends StatelessWidget {
  const _Question(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: theme.textTheme.headlineSmall)),
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _SpendField extends StatelessWidget {
  const _SpendField({required this.initial, required this.onChanged});

  final int? initial;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: initial?.toString(),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
        decoration: const InputDecoration(labelText: 'Amount per month', prefixText: 'R '),
        onChanged: (text) => onChanged(int.tryParse(text)),
      );
}

class _MoneyGoalField extends StatelessWidget {
  const _MoneyGoalField({required this.initial, required this.onChanged});

  final String? initial;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: initial,
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'For example: a car deposit, school fees, a holiday'),
        onChanged: onChanged,
      );
}
