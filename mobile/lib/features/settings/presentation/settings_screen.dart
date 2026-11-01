import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/amount_dialog.dart';
import '../../account/presentation/account_section.dart';
import '../../onboarding/data/profile_repository.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../../tracker/domain/money.dart';
import '../data/app_lock_repository.dart';
import '../data/data_wipe_service.dart';
import 'app_lock_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _toggleLock(BuildContext context, WidgetRef ref, bool enable) async {
    if (enable) {
      await context.push(Routes.pinSetup);
      return;
    }
    final confirmed = await _confirm(
      context,
      title: 'Turn off app lock?',
      body: 'Anyone using this phone will be able to open Reclaim.',
      action: 'Turn off',
    );
    if (confirmed) await ref.read(appLockProvider.notifier).disable();
  }

  Future<void> _chooseGoal(BuildContext context, WidgetRef ref, RecoveryGoalType? current) async {
    final chosen = await showDialog<RecoveryGoalType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('What are you aiming for?'),
        children: [
          for (final g in RecoveryGoalType.values)
            ListTile(
              leading: Icon(g == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(g.label),
              subtitle: Text(g.description),
              onTap: () => Navigator.pop(context, g),
            ),
        ],
      ),
    );
    if (chosen != null) await ref.read(profileRepositoryProvider).setGoalType(chosen);
  }

  Future<void> _editSpend(BuildContext context, WidgetRef ref, int? currentRands) async {
    final cents = await showAmountDialog(
      context,
      title: 'Usual monthly spend on gambling',
      message: 'Used only to estimate how much money you keep. An estimate is fine.',
      initialCents: currentRands == null ? null : currentRands * 100,
      saveLabel: 'Save',
    );
    if (cents != null) await ref.read(profileRepositoryProvider).setUsualMonthlySpend((cents / 100).round());
  }

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete everything on this phone?',
      body: 'Your answers, entries, urges, goals and self-checks will be permanently deleted from this phone, '
          'and this phone will be signed out. An account backup, if you have one, is not affected. '
          'This cannot be undone.',
      action: 'Delete everything',
    );
    if (!confirmed) return;
    await ref.read(dataWipeServiceProvider).wipeEverything();
    ref.invalidate(appLockProvider);
    if (context.mounted) context.go(Routes.welcome);
  }

  static Future<bool> _confirm(BuildContext context, {required String title, required String body, required String action}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lock = ref.watch(appLockProvider).value;
    final biometricsAvailable = ref.watch(_biometricsAvailableProvider).value ?? false;
    final goal = ref.watch(profileProvider).value?.recoveryGoalType;
    final spend = ref.watch(latestOnboardingProvider).value?.approxMonthlySpendRands;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            heading('Privacy'),
            SwitchListTile(
              title: const Text('App lock'),
              subtitle: const Text('Ask for a PIN when Reclaim opens'),
              value: lock?.enabled ?? false,
              onChanged: lock == null ? null : (v) => _toggleLock(context, ref, v),
            ),
            if ((lock?.enabled ?? false) && biometricsAvailable)
              SwitchListTile(
                title: const Text('Unlock with fingerprint or face'),
                value: lock!.biometrics,
                onChanged: (v) => ref.read(appLockProvider.notifier).setBiometrics(v),
              ),
            heading('Your plan'),
            ListTile(
              title: const Text('What you are aiming for'),
              subtitle: Text(goal?.label ?? 'Not set'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _chooseGoal(context, ref, goal),
            ),
            ListTile(
              title: const Text('Usual monthly spend'),
              subtitle: Text(spend == null ? 'Not set: add it to see an estimate of money kept' : formatRands(spend * 100, whole: true)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editSpend(context, ref, spend),
            ),
            heading('Account and backup'),
            const AccountSection(),
            heading('Your data'),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
              title: Text('Delete everything on this phone', style: TextStyle(color: theme.colorScheme.error)),
              subtitle: const Text('Removes all your Reclaim data from this phone'),
              onTap: () => _wipe(context, ref),
            ),
            heading('About'),
            const ListTile(
              title: Text('Reclaim is not a gambling app'),
              subtitle: Text('It has no odds, tips, games or betting promotions, and never will.'),
            ),
            const ListTile(
              title: Text('Not a medical service'),
              subtitle: Text('The self-check is a reflection tool, not a diagnosis. Please speak to a professional for a fuller picture.'),
            ),
          ],
        ),
      ),
    );
  }
}

final _biometricsAvailableProvider = FutureProvider.autoDispose<bool>((ref) => ref.watch(biometricAuthProvider).isAvailable());
