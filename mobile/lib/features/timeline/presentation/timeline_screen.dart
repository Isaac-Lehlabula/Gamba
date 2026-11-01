import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../tracker/data/tracker_repository.dart';
import '../domain/milestones.dart';

/// Milestones of days without gambling. Reached ones are marked plainly; there are no
/// rewards to unlock and nothing to lose.
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final streaks = ref.watch(dashboardProvider)?.streaks;
    final current = streaks?.current ?? 0;
    final longest = streaks?.longest ?? 0;
    final next = Milestones.next(current);

    return Scaffold(
      appBar: AppBar(title: const Text('Your timeline')),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            Text(
              current == 0
                  ? 'Today starts a new run. Every day without gambling counts.'
                  : '$current ${current == 1 ? 'day' : 'days'} without gambling.'
                      '${next == null ? '' : ' ${next.days - current} more to ${next.title.toLowerCase()}.'}',
              style: theme.textTheme.titleMedium,
            ),
            if (longest > current) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Your longest run so far: $longest days.', style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.lg),
            for (final m in Milestones.all) _MilestoneRow(milestone: m, reached: current >= m.days, reachedBefore: longest >= m.days),
          ],
        ),
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({required this.milestone, required this.reached, required this.reachedBefore});

  final Milestone milestone;
  final bool reached;

  /// Reached in an earlier run, though not in the current one.
  final bool reachedBefore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: '${milestone.title}, ${reached ? 'reached' : reachedBefore ? 'reached before' : 'not yet'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              reached ? Icons.check_circle : (reachedBefore ? Icons.check_circle_outline : Icons.circle_outlined),
              color: reached || reachedBefore ? theme.colorScheme.primary : muted,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(milestone.title, style: theme.textTheme.titleMedium?.copyWith(color: reached ? null : muted)),
                  Text(
                    reached || reachedBefore ? milestone.message : 'Ahead of you.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: reached ? null : muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
