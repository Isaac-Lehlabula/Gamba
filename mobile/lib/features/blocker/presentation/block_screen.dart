import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/blocker_repositories.dart';
import '../domain/blocker_models.dart';
import 'blocker_controller.dart';

/// Protection: gambling-site blocking, the protection lock and the user's own blocked sites.
class BlockScreen extends ConsumerStatefulWidget {
  const BlockScreen({super.key});

  @override
  ConsumerState<BlockScreen> createState() => _BlockScreenState();
}

class _BlockScreenState extends ConsumerState<BlockScreen> {
  final _domain = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The service may have started, stopped or blocked things while this screen was away.
      await ref.read(blockerProvider.notifier).refresh();
      // Pick up list changes in the background; failure just keeps the current list.
      if (await ref.read(blockerProvider.notifier).syncBlocklist()) ref.invalidate(activeDomainCountProvider);
    });
  }

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  // Replaces any message still showing, so the newest one is never queued behind it.
  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _busyWhile(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool on) => _busyWhile(() async {
        final blocker = ref.read(blockerProvider.notifier);
        if (on) {
          if (!await blocker.enable()) _say('Protection needs permission to start. You can try again any time.');
        } else if (await blocker.disable() == DisableResult.locked) {
          _say('Protection is locked. Request to unlock it below.');
        }
      });

  Future<void> _addDomain() async {
    final added = await ref.read(blockerProvider.notifier).addCustomDomain(_domain.text);
    if (added == null) {
      _say('That doesn\'t look like a website address. Try something like example.com');
      return;
    }
    _domain.clear();
    _say('$added will be blocked.');
  }

  Future<void> _removeDomain(String domain) async {
    if (!await ref.read(blockerProvider.notifier).removeCustomDomain(domain)) {
      _say('Sites can\'t be removed while protection is locked.');
    }
  }

  Future<void> _lock() async {
    final days = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Lock protection for'),
        children: [
          for (final d in ProtectionRules.durations)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, d), child: Text(d == 1 ? '1 day' : '$d days')),
        ],
      ),
    );
    if (days == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock protection?'),
        content: Text(
          'For ${days == 1 ? '1 day' : '$days days'}, protection can\'t be turned off from Reclaim and your own blocked '
          'sites can\'t be removed. If you need to end it early, you can ask, and it unlocks 24 hours later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lock it')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(protectionRepositoryProvider).startLock(days);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(blockerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Block')),
      body: SafeArea(
        child: switch (state) {
          AsyncData(:final value) when !value.supported => const _NotSupported(),
          AsyncData(:final value) => ListView(
              padding: AppSpacing.screen,
              children: [
                _StatusCard(state: value, busy: _busy, onToggle: _toggle),
                const SizedBox(height: AppSpacing.md),
                const _Limits(),
                const SizedBox(height: AppSpacing.lg),
                _LockCard(onLock: _lock),
                const SizedBox(height: AppSpacing.lg),
                Text('Your own blocked sites', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _domain,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'Website, e.g. example.com'),
                        onSubmitted: (_) => _addDomain(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filledTonal(onPressed: _addDomain, icon: const Icon(Icons.add), tooltip: 'Block this site'),
                  ],
                ),
                for (final d in ref.watch(customDomainsProvider).value ?? const <BlockedDomain>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(d.domain),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Stop blocking ${d.domain}',
                      onPressed: () => _removeDomain(d.domain),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '${ref.watch(activeDomainCountProvider).value ?? 0} gambling sites on the list. '
                  'The list updates automatically.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          AsyncError() => const Center(child: Text("Protection couldn't be loaded. Please try again.")),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.state, required this.busy, required this.onToggle});

  final BlockerState state;
  final bool busy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attempts = state.recentAttempts;
    return Card(
      color: state.running ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(state.running ? Icons.shield : Icons.shield_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(state.running ? 'Protection is on' : 'Protection is off', style: theme.textTheme.titleLarge),
                ),
                Switch(value: state.running, onChanged: busy ? null : onToggle),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.running
                  ? 'Gambling sites are blocked on this phone. An ongoing notification shows while it\'s on.'
                  : 'Turn this on to block gambling sites on this phone, so there\'s time between an urge and a bet.',
              style: theme.textTheme.bodyMedium,
            ),
            if (attempts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Blocked ${attempts.length} ${attempts.length == 1 ? 'time' : 'times'} in the last 7 days, '
                'most recently ${DateFormat('d MMM, HH:mm').format(attempts.first.at)}.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Honest about what blocking can and can't do (docs/BLOCKING.md).
class _Limits extends StatelessWidget {
  const _Limits();

  @override
  Widget build(BuildContext context) => const ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('What this can and can\'t do'),
        childrenPadding: EdgeInsets.only(bottom: AppSpacing.sm),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reclaim filters website lookups on this phone, so most gambling sites and apps can\'t connect. '
            'It runs as a local VPN on the phone: your browsing is never sent to Reclaim.\n\n'
            'No app can block everything. Some apps and browsers use their own private lookups, and new gambling '
            'sites appear all the time. It also can\'t run alongside another VPN app, and you can switch it off in '
            'your phone\'s settings. It\'s designed to put a pause between an urge and a bet, not to be unbreakable.',
          ),
        ],
      );
}

class _LockCard extends ConsumerWidget {
  const _LockCard({required this.onLock});

  final VoidCallback onLock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final lock = ref.watch(protectionLockProvider).value;
    final removal = ref.watch(pendingRemovalProvider).value;
    final repo = ref.read(protectionRepositoryProvider);
    final fmt = DateFormat('d MMMM, HH:mm');

    final active = lock != null && now.isBefore(lock.expiresAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Protection lock', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (!active) ...[
              const Text('Commit to keeping protection on for a while. In a hard moment, it\'s one less decision to make.'),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: onLock, child: const Text('Lock protection')),
            ] else ...[
              Text('Locked until ${fmt.format(lock.expiresAt)}.'),
              const SizedBox(height: AppSpacing.sm),
              if (removal == null)
                TextButton(onPressed: repo.requestRemoval, child: const Text('Ask to unlock early'))
              else if (now.isBefore(removal.coolingOffEndsAt)) ...[
                Text('You asked to unlock. You can unlock after ${fmt.format(removal.coolingOffEndsAt)}, if you still want to.'),
                TextButton(onPressed: repo.cancelRemoval, child: const Text('Keep it locked')),
              ] else ...[
                const Text('The 24-hour wait is over. You can unlock now, or keep it locked.'),
                Row(
                  children: [
                    TextButton(onPressed: repo.completeRemoval, child: const Text('Unlock')),
                    TextButton(onPressed: repo.cancelRemoval, child: const Text('Keep it locked')),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _NotSupported extends StatelessWidget {
  const _NotSupported();

  @override
  Widget build(BuildContext context) => ListView(
        padding: AppSpacing.screen,
        children: [
          Icon(Icons.shield_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: AppSpacing.md),
          Text('Not available on this phone yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'On iPhone, blocking will use Apple\'s Screen Time protections. That needs Apple\'s approval, which is in '
            'progress. Until then, iPhone\'s own Screen Time settings can restrict websites.',
          ),
        ],
      );
}
