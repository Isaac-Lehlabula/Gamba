import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/data/profile_repository.dart';
import '../../tracker/data/tracker_repository.dart';
import '../../tracker/domain/money.dart';
import '../data/urge_repository.dart';
import '../domain/urge_models.dart';

/// The cooling-off pause, then the outcome. The countdown is worked out from the stored start
/// time, so leaving the app and coming back carries on where it was.
class UrgeSessionScreen extends ConsumerStatefulWidget {
  const UrgeSessionScreen({required this.urgeId, super.key});

  final String urgeId;

  @override
  ConsumerState<UrgeSessionScreen> createState() => _UrgeSessionScreenState();
}

class _UrgeSessionScreenState extends ConsumerState<UrgeSessionScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _resolve(UrgeOutcome outcome) => ref.read(urgeRepositoryProvider).resolve(widget.urgeId, outcome);

  @override
  Widget build(BuildContext context) {
    final urge = ref.watch(urgeProvider(widget.urgeId));
    return Scaffold(
      appBar: AppBar(title: const Text('Pause')),
      body: SafeArea(
        child: switch (urge) {
          AsyncData(value: final u?) when u.outcome != null => _Outcome(outcome: u.outcome!),
          AsyncData(value: final u?) => _pauseOrCheckIn(context, u),
          AsyncData() => const Center(child: Text('This pause is no longer on this phone.')),
          AsyncError() => const Center(child: Text("This pause couldn't be loaded.")),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _pauseOrCheckIn(BuildContext context, Urge urge) {
    final theme = Theme.of(context);
    final total = Duration(minutes: urge.coolingOffMinutes);
    final left = UrgePause.remaining(startedAt: urge.startedAt, minutes: urge.coolingOffMinutes, now: ref.read(clockProvider)());
    final over = left == Duration.zero;

    return ListView(
      padding: AppSpacing.screen,
      children: [
        Center(
          child: SizedBox.square(
            dimension: 200,
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: over ? 1 : 1 - left.inMilliseconds / total.inMilliseconds,
                  strokeWidth: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                Center(
                  child: Semantics(
                    liveRegion: true,
                    label: over ? 'Pause finished' : '${UrgePause.format(left)} left',
                    child: ExcludeSemantics(
                      child: Text(over ? 'Done' : UrgePause.format(left), style: theme.textTheme.displaySmall),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (over) ...[
          Text('The pause is over. How are you feeling now?', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: () => _resolve(UrgeOutcome.passed), child: const Text('The urge has passed')),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => ref.read(urgeRepositoryProvider).extend(widget.urgeId),
            child: const Text('I need ${UrgePause.extensionMinutes} more minutes'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: () => _resolve(UrgeOutcome.gambled), child: const Text('I gambled')),
        ] else ...[
          Text(
            "You don't have to decide anything until this finishes.",
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Reasons(),
          const SizedBox(height: AppSpacing.md),
          _Section(title: 'Things that can help', lines: UrgeGuidance.tipsFor(urge.trigger)),
          const SizedBox(height: AppSpacing.md),
          const _Breathing(),
          const SizedBox(height: AppSpacing.md),
          const _Section(title: 'Ground yourself', lines: UrgeGuidance.grounding),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(onPressed: () => _resolve(UrgeOutcome.passed), child: const Text("I'm feeling better now")),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: () => _resolve(UrgeOutcome.gambled), child: const Text('I gambled')),
        ],
      ],
    );
  }
}

/// The user's own reasons to wait: their run, their money, their goal.
class _Reasons extends ConsumerWidget {
  const _Reasons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardProvider);
    final goal = ref.watch(latestOnboardingProvider).value?.moneyGoalPreference;
    final days = summary?.streaks.current ?? 0;
    final lines = [
      if (days > 0) "You've had $days ${days == 1 ? 'day' : 'days'} without gambling.",
      if (summary?.moneyKeptCents case final kept? when kept > 0)
        "That's about ${formatRands(kept, whole: true)} kept so far (an estimate).",
      if (goal != null) "You're working toward: $goal.",
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return _Section(title: 'Remember why', lines: lines, highlighted: true);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.lines, this.highlighted = false});

  final String title;
  final List<String> lines;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: highlighted ? theme.colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(line, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}

/// Breathing guidance, with an optional animated circle to follow.
class _Breathing extends StatefulWidget {
  const _Breathing();

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> with SingleTickerProviderStateMixin {
  // In for 4 seconds, hold for 4, out for 6.
  static const _cycle = Duration(seconds: 14);

  // Created eagerly: a lazy controller would first be built inside dispose(), which throws.
  late final AnimationController _controller;
  bool _guiding = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _cycle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _guiding = !_guiding);
    _guiding ? _controller.repeat() : _controller.stop();
  }

  static (double scale, String label) _phase(double t) {
    final seconds = t * 14;
    if (seconds < 4) return (0.6 + 0.4 * seconds / 4, 'Breathe in');
    if (seconds < 8) return (1.0, 'Hold');
    return (1.0 - 0.4 * (seconds - 8) / 6, 'Breathe out');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Breathe', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(UrgeGuidance.breathing, style: theme.textTheme.bodyMedium),
            if (_guiding)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final (scale, label) = _phase(_controller.value);
                  return SizedBox(
                    height: 160,
                    child: Center(
                      child: Container(
                        width: 140 * scale,
                        height: 140 * scale,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
                        child: Text(label, style: theme.textTheme.titleMedium),
                      ),
                    ),
                  );
                },
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _toggle, child: Text(_guiding ? 'Stop' : 'Breathe with me')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.outcome});

  final UrgeOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gambled = outcome == UrgeOutcome.gambled;
    return ListView(
      padding: AppSpacing.screen,
      children: [
        Icon(gambled ? Icons.favorite_outline : Icons.spa_outlined, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: AppSpacing.md),
        Text(
          switch (outcome) {
            UrgeOutcome.passed => UrgeGuidance.passed,
            UrgeOutcome.gambled => UrgeGuidance.gambled,
            UrgeOutcome.abandoned => 'This pause was closed before it finished.',
          },
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (gambled) ...[
          FilledButton(onPressed: () => context.pushReplacement(Routes.newEntry), child: const Text('Log what you spent')),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: () => context.go(Routes.home), child: const Text('Not now')),
        ] else
          FilledButton(onPressed: () => context.go(Routes.home), child: const Text('Back to home')),
      ],
    );
  }
}
