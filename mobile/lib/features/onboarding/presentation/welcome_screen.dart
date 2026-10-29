import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// First screen. Its job is to make the app feel safe and private before asking anything.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            const SizedBox(height: AppSpacing.xl),
            Text('This is your space.', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Reclaim helps you understand your gambling, protect your money and get through urges, at your own pace.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            const _Promise(icon: Icons.phone_android, title: 'Everything stays on this phone', body: 'Your answers are encrypted and stored here, not sent anywhere.'),
            const _Promise(icon: Icons.person_off_outlined, title: 'No account needed', body: 'No email, no name. You can add a backup later if you want one.'),
            const _Promise(icon: Icons.favorite_outline, title: 'No judgement', body: "Wherever you're starting from, it's a good place to start."),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: () => context.go(Routes.onboarding), child: const Text("Let's begin")),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Reclaim is not a gambling app. It has no odds, tips or betting promotions.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
