import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/amount_dialog.dart';
import '../../tracker/domain/money.dart';
import '../data/goal_repository.dart';
import '../domain/goal_models.dart';

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({required this.goalId, super.key});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(goalViewsProvider)?.where((v) => v.goal.id == goalId).firstOrNull;
    final loading = ref.watch(goalViewsProvider) == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(view?.goal.name ?? 'Goal'),
        actions: [
          if (view != null)
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit goal', onPressed: () => context.push(Routes.editGoal(goalId))),
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : view == null
                ? const Center(child: Text('This goal is no longer on this phone.'))
                : _Body(view: view),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.view});

  final GoalView view;

  Future<void> _addManual(BuildContext context, WidgetRef ref) async {
    final cents = await showAmountDialog(
      context,
      title: 'Add money you have set aside',
      message: 'Money you have actually put away for this goal.',
    );
    if (cents != null) await ref.read(goalRepositoryProvider).addContribution(view.goal.id, cents, ContributionSource.manual);
  }

  Future<void> _moveEstimate(BuildContext context, WidgetRef ref, int availableCents) async {
    final suggested = view.progress.remainingCents < availableCents ? view.progress.remainingCents : availableCents;
    final cents = await showAmountDialog(
      context,
      title: 'Count estimated savings',
      message: 'This is an estimate of money kept by not gambling, not money in a bank account. '
          'Moving it here helps you see what it could add up to.',
      initialCents: suggested,
      maxCents: availableCents,
    );
    if (cents != null) {
      await ref.read(goalRepositoryProvider).addContribution(view.goal.id, cents, ContributionSource.estimatedSavings);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, GoalContribution c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this amount?'),
        content: Text('${formatRands(c.amountCents)} will no longer count toward this goal.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(goalRepositoryProvider).deleteContribution(c.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = view.progress;
    final available = ref.watch(availableEstimatedSavingsProvider);
    final monthly = p.monthlyNeededCents(targetDate: view.goal.targetDate, now: ref.watch(clockProvider)());
    final contributions = [
      for (final c in ref.watch(goalContributionsProvider).value ?? const <GoalContribution>[])
        if (c.goalId == view.goal.id) c,
    ];
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return ListView(
      padding: AppSpacing.screen,
      children: [
        Text(
          p.isReached ? 'You reached this goal.' : '${formatRands(p.savedCents, whole: true)} of ${formatRands(p.targetCents, whole: true)}',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(value: p.fraction, minHeight: 10, borderRadius: BorderRadius.circular(5)),
        const SizedBox(height: AppSpacing.sm),
        if (!p.isReached) Text('${formatRands(p.remainingCents, whole: true)} to go', style: theme.textTheme.bodyLarge),
        if (view.goal.targetDate case final date?) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            monthly == null
                ? 'Target date: ${DateFormat('d MMMM y').format(date)}'
                : 'About ${formatRands(monthly, whole: true)} a month to reach it by ${DateFormat('MMMM y').format(date)}.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: () => _addManual(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add money I have set aside'),
        ),
        if (available != null) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: available > 0 && !p.isReached ? () => _moveEstimate(context, ref, available) : null,
            child: Text(
              available > 0
                  ? 'Count estimated savings (${formatRands(available, whole: true)} available)'
                  : 'No estimated savings left to count',
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Estimated savings are based on what you usually spent on gambling. They are an estimate, not a guarantee.', style: muted),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text('Counted so far', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (contributions.isEmpty)
          Text('Nothing yet.', style: theme.textTheme.bodyMedium)
        else
          Card(
            child: Column(
              children: [
                for (final c in contributions)
                  ListTile(
                    title: Text(formatRands(c.amountCents)),
                    subtitle: Text('${c.source.label} · ${DateFormat('d MMM y').format(c.occurredAt)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove',
                      onPressed: () => _remove(context, ref, c),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
