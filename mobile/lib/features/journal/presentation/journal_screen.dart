import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/theme/app_theme.dart';
import '../data/journal_repository.dart';
import '../domain/insights.dart';
import '../domain/journal_models.dart';

/// The private journal: what the user has noticed, and the patterns in it.
class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(journalEntriesProvider).value ?? const <JournalEntry>[];
    final insights = ref.watch(insightsProvider);
    final urgeCount = ref.watch(urgeEventsProvider).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            Text(
              'A private place to note how you feel, what sets off urges, and what helps. Only you can see it.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () => context.push(Routes.newJournalEntry),
              icon: const Icon(Icons.edit_note),
              label: const Text('Write an entry'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patterns', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    if (insights.isEmpty)
                      Text(
                        urgeCount < Insights.minimumEvents
                            ? 'Patterns appear once you\'ve recorded a few urges (${Insights.minimumEvents - urgeCount} more). '
                                'They include urges from "I feel like gambling".'
                            : 'No clear patterns yet. That can change as you record more.',
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      for (final insight in insights)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.insights_outlined, size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(child: Text(insight.text, style: theme.textTheme.bodyMedium)),
                            ],
                          ),
                        ),
                    if (insights.isNotEmpty)
                      Text(Insights.disclaimer, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (entries.isEmpty)
              Text('No entries yet.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              Card(
                child: Column(
                  children: [
                    for (final e in entries)
                      ListTile(
                        title: Text(_summary(e)),
                        subtitle: Text(
                          [DateFormat('EEE d MMM, HH:mm').format(e.occurredAt), if (e.note != null) e.note!].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(Routes.journalEntry(e.id)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _summary(JournalEntry e) => [
        if (e.mood case final m?) 'Mood: ${MoodScale.labels[m]}',
        if (e.urgeIntensity case final i?) 'Urge $i/5',
        if (e.trigger case final t?) t.label,
        if (e.outcome case final o?) o.label,
      ].join(' · ').ifEmpty('Note');
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
