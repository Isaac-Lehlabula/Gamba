import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../assessment/data/assessment_repository.dart';
import '../../tracker/presentation/tracker_section.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(assessmentHistoryProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            const TrackerSection(),
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
