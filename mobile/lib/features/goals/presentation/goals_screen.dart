import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/data/profile_repository.dart';
import '../data/goal_repository.dart';
import 'goal_widgets.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final views = ref.watch(goalViewsProvider);
    final suggestion = ref.watch(latestOnboardingProvider).value?.moneyGoalPreference;

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      body: SafeArea(
        child: views == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: AppSpacing.screen,
                children: [
                  if (views.isEmpty) ...[
                    Text(
                      'A goal gives the money you keep somewhere to go. It can be anything that matters to you.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  for (final view in views) ...[
                    GoalCard(view: view, onTap: () => context.push(Routes.goal(view.goal.id))),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  // Offer the goal named during onboarding until it (or any goal) exists.
                  if (views.isEmpty && suggestion != null) ...[
                    FilledButton(
                      onPressed: () => context.push(Routes.newGoal(name: suggestion)),
                      child: Text('Make "$suggestion" a goal'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(onPressed: () => context.push(Routes.newGoal()), child: const Text('Add a different goal')),
                  ] else
                    FilledButton.icon(
                      onPressed: () => context.push(Routes.newGoal()),
                      icon: const Icon(Icons.add),
                      label: const Text('Add a goal'),
                    ),
                ],
              ),
      ),
    );
  }
}
