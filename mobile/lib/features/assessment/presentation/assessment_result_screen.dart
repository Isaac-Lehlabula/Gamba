import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/assessment_repository.dart';
import '../domain/questionnaire.dart';

/// The result, framed around next steps rather than the score.
class AssessmentResultScreen extends ConsumerWidget {
  const AssessmentResultScreen({required this.resultId, super.key});

  final String resultId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(assessmentResultProvider(resultId));
    return Scaffold(
      appBar: AppBar(title: const Text('Your self-check')),
      body: SafeArea(
        child: switch (result) {
          AsyncData(value: final r?) => _Body(level: r.riskLevel, score: r.score),
          AsyncData() => const Center(child: Text('This result is no longer on this phone.')),
          AsyncError() => const Center(child: Text("This result couldn't be loaded.")),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.level, required this.score});

  final RiskLevel level;
  final int score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guidance = Questionnaire.guidanceFor(level);

    return ListView(
      padding: AppSpacing.screen,
      children: [
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.label, style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(guidance.summary, style: theme.textTheme.bodyLarge),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Score: $score of ${Questionnaire.maxScore}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('What might help', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        for (final action in guidance.actions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
            title: Text(action.title),
            subtitle: Text(action.description),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          Questionnaire.disclaimer,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(onPressed: () => context.go(Routes.home), child: const Text('Continue')),
      ],
    );
  }
}
