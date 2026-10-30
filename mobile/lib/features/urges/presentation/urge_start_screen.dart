import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/choice_tile.dart';
import '../../onboarding/data/profile_repository.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../data/urge_repository.dart';
import '../domain/urge_models.dart';

/// Two quick steps, because someone opening this is in the middle of an urge: what's going
/// on, then how long to pause.
class UrgeStartScreen extends ConsumerStatefulWidget {
  const UrgeStartScreen({super.key});

  @override
  ConsumerState<UrgeStartScreen> createState() => _UrgeStartScreenState();
}

class _UrgeStartScreenState extends ConsumerState<UrgeStartScreen> {
  TriggerType? _trigger;
  int? _intensity;
  int _minutes = UrgePause.defaultMinutes;
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final id = await ref.read(urgeRepositoryProvider).start(trigger: _trigger!, intensity: _intensity, minutes: _minutes);
      if (mounted) context.pushReplacement(Routes.urgeSession(id));
    } catch (_) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That didn't start. Please try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final onTrigger = _trigger == null;
    return PopScope(
      canPop: onTrigger,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _trigger = null);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: onTrigger ? const CloseButton() : BackButton(onPressed: () => setState(() => _trigger = null)),
          title: const Text('I feel like gambling'),
        ),
        body: SafeArea(child: onTrigger ? _triggerStep(context) : _pauseStep(context)),
      ),
    );
  }

  Widget _triggerStep(BuildContext context) {
    final theme = Theme.of(context);
    // Triggers the user named during onboarding come first.
    final known = ref.watch(latestOnboardingProvider).value?.triggers ?? const [];
    final ordered = [...known, ...TriggerType.values.where((t) => !known.contains(t))];

    return ListView(
      padding: AppSpacing.screen,
      children: [
        Text(UrgeGuidance.opening, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.lg),
        Semantics(header: true, child: Text("What's going on right now?", style: theme.textTheme.headlineSmall)),
        const SizedBox(height: AppSpacing.md),
        for (final trigger in ordered)
          ChoiceTile(label: trigger.label, selected: false, onTap: () => setState(() => _trigger = trigger)),
      ],
    );
  }

  Widget _pauseStep(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: AppSpacing.screen,
      children: [
        Semantics(header: true, child: Text('How strong is it?', style: theme.textTheme.headlineSmall)),
        const SizedBox(height: AppSpacing.xs),
        Text('Optional.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var level = 1; level <= 5; level++)
              ChoiceChip(
                label: Text('$level'),
                tooltip: intensityLabels[level],
                selected: _intensity == level,
                onSelected: (selected) => setState(() => _intensity = selected ? level : null),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(intensityLabels[1]!, style: theme.textTheme.bodySmall),
            Text(intensityLabels[5]!, style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Semantics(header: true, child: Text('Take a pause before you decide', style: theme.textTheme.headlineSmall)),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final minutes in UrgePause.options)
              ChoiceChip(
                label: Text('$minutes min'),
                selected: _minutes == minutes,
                onSelected: (_) => setState(() => _minutes = minutes),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: _starting ? null : _start,
          child: _starting
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Start the pause'),
        ),
      ],
    );
  }
}
