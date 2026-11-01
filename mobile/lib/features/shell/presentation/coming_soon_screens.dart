import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// An honest placeholder: says what is coming and why, rather than a dead button.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({required this.title, required this.icon, required this.message, this.note, super.key});

  final String title;
  final IconData icon;
  final String message;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text('Coming soon', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: theme.textTheme.bodyLarge),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(note!, style: theme.textTheme.bodyMedium),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SupportComingSoonScreen extends StatelessWidget {
  const SupportComingSoonScreen({super.key});

  @override
  Widget build(BuildContext context) => const ComingSoonScreen(
        title: 'Support',
        icon: Icons.volunteer_activism_outlined,
        message:
            "We're putting together South African support services: counselling, gambling help and financial advice. "
            "We're checking every contact before we publish it, so you can rely on it when you need it.",
        note: 'If you or someone else is in danger right now, please contact your local emergency services.',
      );
}
