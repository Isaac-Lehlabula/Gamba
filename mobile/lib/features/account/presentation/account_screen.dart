import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/account_repository.dart';

/// Create an account or sign in, for the optional backup. Using Reclaim never requires this.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(accountRepositoryProvider);
    try {
      if (_creating) {
        final profileId = await ref.read(localProfileIdProvider.future);
        await repo.register(_email.text.trim(), _password.text, localProfileId: profileId!);
      } else {
        await repo.signIn(_email.text.trim(), _password.text);
      }
      ref.invalidate(signedInEmailProvider);
      if (mounted) context.pop(true);
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Back up my data')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: AppSpacing.screen,
            children: [
              Text(
                'An account is optional. It keeps a copy of your Reclaim data on our servers, so it isn\'t lost if '
                'something happens to this phone. All we need is an email address and a password.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your data travels encrypted, and your notes are encrypted again on our servers. '
                'You can delete the account and its backup at any time.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Create account')),
                  ButtonSegment(value: false, label: Text('Sign in')),
                ],
                selected: {_creating},
                onSelectionChanged: _busy ? null : (s) => setState(() => _creating = s.single),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email address',
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(labelText: _creating ? 'Choose a password' : 'Password'),
                validator: (v) => _creating && (v ?? '').length < 8 ? 'Use at least 8 characters' : ((v ?? '').isEmpty ? 'Enter your password' : null),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_creating ? 'Create account' : 'Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
