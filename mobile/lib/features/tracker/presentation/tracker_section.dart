import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/tracker_repository.dart';
import '../domain/money.dart';

/// Totals for a chosen period, plus the list of entries. Shown on the Progress tab.
class TrackerSection extends ConsumerStatefulWidget {
  const TrackerSection({super.key});

  @override
  ConsumerState<TrackerSection> createState() => _TrackerSectionState();
}

class _TrackerSectionState extends ConsumerState<TrackerSection> {
  StatsPeriod _period = StatsPeriod.month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = ref.watch(gamblingEntriesProvider).value ?? const [];
    final start = _period.startFor(ref.watch(clockProvider)());
    final totals = GamblingTotals.of([
      for (final e in entries)
        if (start == null || !e.occurredAt.isBefore(start)) (type: e.entryType, amountCents: e.amountCents),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Money and gambling', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in StatsPeriod.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(label: Text(p.label), selected: _period == p, onSelected: (_) => setState(() => _period = p)),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TotalsCard(totals: totals),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: () => context.push(Routes.newEntry),
          icon: const Icon(Icons.add),
          label: const Text('Add an entry'),
        ),
        const SizedBox(height: AppSpacing.md),
        if (entries.isEmpty)
          Text(
            'Nothing logged yet. Writing down what goes in and out is one of the clearest ways to see the real cost.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          Card(
            child: Column(
              children: [
                for (final e in entries)
                  ListTile(
                    leading: Icon(_iconFor(e.entryType), color: theme.colorScheme.onSurfaceVariant),
                    title: Text('${e.entryType.label} · ${formatRands(e.amountCents)}'),
                    subtitle: Text([e.platformName, DateFormat('d MMM y').format(e.occurredAt)].nonNulls.join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.editEntry(e.id)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // Deliberately neutral: a win gets no special colour or celebration.
  static IconData _iconFor(GamblingEntryType type) => switch (type) {
        GamblingEntryType.deposit => Icons.north_east,
        GamblingEntryType.withdrawal => Icons.south_west,
        GamblingEntryType.loss => Icons.remove,
        GamblingEntryType.win => Icons.add,
      };
}

/// Deposited / withdrawn / net loss, used on Progress and Home.
class TotalsCard extends StatelessWidget {
  const TotalsCard({required this.totals, super.key});

  final GamblingTotals totals;

  @override
  Widget build(BuildContext context) {
    final net = totals.netLoss;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          children: [
            _Row('Deposited', formatRands(totals.deposited)),
            _Row('Withdrawn', formatRands(totals.withdrawn)),
            if (totals.lost > 0 || totals.won > 0) ...[
              _Row('Lost', formatRands(totals.lost)),
              _Row('Won', formatRands(totals.won)),
            ],
            const Divider(),
            _Row(net >= 0 ? 'Net loss' : 'Net (ahead)', formatRands(net.abs()), emphasise: true),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.emphasise = false});

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final style = emphasise ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
