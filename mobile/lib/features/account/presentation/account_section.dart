import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../data/account_repository.dart';
import '../data/backup_service.dart';

/// The "Account and backup" part of Settings.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  bool _busy = false;

  // Replaces any message still showing, so the newest one is never queued behind it.
  void _show(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on AccountException catch (e) {
      if (mounted) _show(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backUp() => _run(() async {
        await ref.read(backupServiceProvider).backUp();
        ref.invalidate(lastBackupAtProvider);
        if (mounted) _show('Your data is backed up.');
      });

  Future<void> _signOut() => _run(() async {
        await ref.read(accountRepositoryProvider).signOut();
        ref.invalidate(signedInEmailProvider);
      });

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your account and its backup will be permanently deleted from our servers after 7 days. '
          'Everything on this phone stays here.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete account')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref.read(accountRepositoryProvider).deleteAccount();
      ref.invalidate(signedInEmailProvider);
      if (mounted) _show('Your account will be deleted.');
    });
  }

  Future<void> _openAccount() async {
    final signedIn = await context.push<bool>(Routes.account);
    if (signedIn == true && mounted) await _backUp();
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(signedInEmailProvider);
    final last = ref.watch(lastBackupAtProvider).value;

    if (email.isLoading) return const ListTile(title: Text('Account'), subtitle: LinearProgressIndicator());
    final signedIn = email.value;

    if (signedIn == null) {
      return ListTile(
        leading: const Icon(Icons.cloud_upload_outlined),
        title: const Text('Back up my data'),
        subtitle: const Text('Optional: create an account to keep a copy off this phone'),
        trailing: const Icon(Icons.chevron_right),
        enabled: !_busy,
        onTap: _openAccount,
      );
    }

    return Column(
      children: [
        ListTile(leading: const Icon(Icons.account_circle_outlined), title: const Text('Signed in'), subtitle: Text(signedIn)),
        ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Back up now'),
          subtitle: Text(last == null ? 'Not backed up yet' : 'Last backup: ${DateFormat('d MMMM y, HH:mm').format(last.toLocal())}'),
          trailing: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          enabled: !_busy,
          onTap: _backUp,
        ),
        const ListTile(
          dense: true,
          subtitle: Text('Restoring a backup onto a new phone is coming in a later update.'),
        ),
        ListTile(title: const Text('Sign out'), enabled: !_busy, onTap: _signOut),
        ListTile(title: const Text('Delete my account'), enabled: !_busy, onTap: _deleteAccount),
      ],
    );
  }
}
