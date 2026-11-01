import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../assessment/data/assessment_repository.dart';
import '../../dashboard/domain/dashboard.dart';
import '../../goals/data/goal_repository.dart';
import '../../goals/presentation/goal_widgets.dart';
import '../../onboarding/data/profile_repository.dart';
import '../../tracker/data/tracker_repository.dart';
import '../../tracker/domain/money.dart';
import '../../tracker/presentation/tracker_section.dart';
import '../../urges/data/urge_repository.dart';

/// The recovery dashboard.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String greetingFor(DateTime now) => switch (now.hour) {
        < 12 => 'Good morning',
        < 18 => 'Good afternoon',
        _ => 'Good evening',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final summary = ref.watch(dashboardProvider);
    final moneyGoal = ref.watch(latestOnboardingProvider).value?.moneyGoalPreference;
    final latestCheck = ref.watch(assessmentHistoryProvider).value?.firstOrNull;
    final activeUrge = ref.watch(activeUrgeProvider).value;
    // The first goal not yet reached; otherwise the most recent one.
    final goalViews = ref.watch(goalViewsProvider) ?? const <GoalView>[];
    final featuredGoal = goalViews.where((v) => !v.progress.isReached).firstOrNull ?? goalViews.lastOrNull;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            Row(
              children: [
                Expanded(child: Text(greetingFor(now), style: theme.textTheme.headlineMedium)),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () => context.push(Routes.settings),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (activeUrge != null)
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  leading: const Icon(Icons.hourglass_bottom),
                  title: const Text('Your pause is still going'),
                  subtitle: const Text('Tap to go back to it.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.urgeSession(activeUrge.id)),
                ),
              )
            else
              FilledButton.icon(
                onPressed: () => context.push(Routes.urge),
                icon: const Icon(Icons.self_improvement),
                label: const Text('I feel like gambling'),
              ),
            const SizedBox(height: AppSpacing.lg),
            if (summary != null) ...[
              _StreakCard(streaks: summary.streaks),
              if (summary.moneyKeptCents case final kept?) ...[
                const SizedBox(height: AppSpacing.md),
                _MoneyKeptCard(
                  keptCents: kept,
                  usualMonthlyRands: summary.usualMonthlySpendRands!,
                  goal: featuredGoal == null ? moneyGoal : null,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (featuredGoal != null)
                GoalCard(view: featuredGoal, onTap: () => context.push(Routes.goal(featuredGoal.goal.id)))
              else
                _GoalPrompt(suggestion: moneyGoal),
              const SizedBox(height: AppSpacing.lg),
              Text('This month', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              TotalsCard(totals: summary.thisMonth),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.newEntry),
                icon: const Icon(Icons.add),
                label: const Text('Log an entry'),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                leading: Icon(Icons.fact_check_outlined, color: theme.colorScheme.primary),
                title: Text(latestCheck == null ? 'Take a two-minute self-check' : 'Your latest self-check'),
                subtitle: Text(
                  latestCheck == null
                      ? 'A clearer picture of how gambling is affecting you, and what might help.'
                      : '${latestCheck.riskLevel.label} · ${DateFormat('d MMMM').format(latestCheck.createdAt)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => latestCheck == null
                    ? context.push(Routes.assessment)
                    : context.push(Routes.assessmentResult(latestCheck.id)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streaks});

  final Streaks streaks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onCard = theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer);
    final days = streaks.current;

    return Card(
      color: theme.colorScheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // The run and journey day lead naturally into the milestone timeline.
        onTap: () => context.push(Routes.timeline),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (days > 0) ...[
                Text(days == 1 ? '1 day' : '$days days', style: theme.textTheme.displaySmall),
                Text('without gambling', style: onCard),
              ] else
                // Logged gambling today: acknowledge it without judgement.
                Text("You've logged gambling today. Being honest about it is part of the work, and tomorrow starts a new run.",
                    style: onCard),
              const SizedBox(height: AppSpacing.md),
              Text(
                [
                  'Day ${streaks.journeyDay} of your journey',
                  if (streaks.longest > days) 'Longest run: ${streaks.longest} days',
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoneyKeptCard extends StatelessWidget {
  const _MoneyKeptCard({required this.keptCents, required this.usualMonthlyRands, required this.goal});

  final int keptCents;
  final int usualMonthlyRands;
  final String? goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estimated money kept', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(formatRands(keptCents, whole: true), style: theme.textTheme.headlineSmall),
            if (goal != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Toward: $goal', style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              'An estimate, not a guarantee: based on the ${formatRands(usualMonthlyRands * 100, whole: true)} a month '
              'you said you usually spend, minus what you have logged since starting.',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown until the first goal exists, suggesting the one named during onboarding.
class _GoalPrompt extends StatelessWidget {
  const _GoalPrompt({required this.suggestion});

  final String? suggestion;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          leading: Icon(Icons.savings_outlined, color: Theme.of(context).colorScheme.primary),
          title: Text(suggestion == null ? 'Set a goal' : 'Working toward: $suggestion'),
          subtitle: const Text('Give the money you keep somewhere to go.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.goals),
        ),
      );
}
