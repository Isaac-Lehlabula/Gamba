import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../assessment/data/assessment_repository.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../tracker/domain/money.dart';
import '../../tracker/presentation/tracker_section.dart';
import '../../urges/data/urge_repository.dart';
import '../../urges/domain/urge_models.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(assessmentHistoryProvider).value ?? const [];
    final monthStart = StatsPeriod.month.startFor(ref.watch(clockProvider)())!;
    final urges = [
      for (final u in ref.watch(urgeHistoryProvider).value ?? const <Urge>[])
        if (!u.startedAt.isBefore(monthStart)) u,
    ];
    final passed = urges.where((u) => u.outcome == UrgeOutcome.passed).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            const TrackerSection(),
            const SizedBox(height: AppSpacing.xl),
            Card(
              child: ListTile(
                leading: Icon(Icons.timeline, color: theme.colorScheme.primary),
                title: const Text('Your timeline'),
                subtitle: const Text('Milestones of days without gambling'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.timeline),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: ListTile(
                leading: Icon(Icons.savings_outlined, color: theme.colorScheme.primary),
                title: const Text('Goals'),
                subtitle: const Text('What the money you keep is going toward'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.goals),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Urges', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              urges.isEmpty
                  ? 'When an urge hits, tap "I feel like gambling" on Home for a short pause.'
                  : 'This month: ${urges.length} ${urges.length == 1 ? 'urge' : 'urges'}, '
                      '$passed you rode out with a pause.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Self-checks', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            if (history.isEmpty)
              Text(
                "You haven't done a self-check yet. Doing one now and again shows how things are changing.",
                style: theme.textTheme.bodyLarge,
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final result in history)
                      ListTile(
                        title: Text(result.riskLevel.label),
                        subtitle: Text(DateFormat('d MMMM y').format(result.createdAt)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(Routes.assessmentResult(result.id)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () => context.push(Routes.assessment),
              child: Text(history.isEmpty ? 'Take the self-check' : 'Take it again'),
            ),
          ],
        ),
      ),
    );
  }
}
