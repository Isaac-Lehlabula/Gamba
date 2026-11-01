import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../tracker/domain/money.dart';
import '../data/goal_repository.dart';
import '../domain/goal_models.dart';

IconData goalIcon(GoalCategory category) => switch (category) {
      GoalCategory.emergencyFund => Icons.health_and_safety_outlined,
      GoalCategory.car => Icons.directions_car_outlined,
      GoalCategory.houseDeposit => Icons.home_outlined,
      GoalCategory.debt => Icons.receipt_long_outlined,
      GoalCategory.holiday => Icons.beach_access_outlined,
      GoalCategory.education => Icons.school_outlined,
      GoalCategory.family => Icons.family_restroom_outlined,
      GoalCategory.savings => Icons.savings_outlined,
      GoalCategory.custom => Icons.flag_outlined,
    };

/// "R 8 400 of R 20 000", with a progress bar. Reaching a goal is acknowledged plainly, with
/// no celebration effects.
class GoalCard extends StatelessWidget {
  const GoalCard({required this.view, required this.onTap, super.key});

  final GoalView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = view.progress;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(goalIcon(view.goal.category), color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(view.goal.name, style: theme.textTheme.titleMedium)),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                label: '${(p.fraction * 100).round()} percent of the way',
                child: LinearProgressIndicator(value: p.fraction, minHeight: 8, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                p.isReached
                    ? 'Reached: ${formatRands(p.savedCents, whole: true)}'
                    : '${formatRands(p.savedCents, whole: true)} of ${formatRands(p.targetCents, whole: true)}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
