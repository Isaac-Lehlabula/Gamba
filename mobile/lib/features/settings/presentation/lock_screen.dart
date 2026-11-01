import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'app_lock_controller.dart';

/// Shown instead of the app while it is locked. Deliberately plain: nothing on it hints at
/// what the app is for, in case someone else is looking at the screen.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pin = TextEditingController();
  String? _message;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Offer biometrics straight away when they're switched on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(appLockProvider).value?.biometrics ?? false) unawaited(_biometrics());
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _biometrics() => ref.read(appLockProvider.notifier).unlockWithBiometrics();

  Future<void> _submit() async {
    if (_checking || _pin.text.isEmpty) return;
    setState(() => _checking = true);
    final result = await ref.read(appLockProvider.notifier).unlockWithPin(_pin.text);
    if (!mounted) return;
    _pin.clear();
    setState(() {
      _checking = false;
      _message = switch (result) {
        UnlockResult.unlocked => null,
        UnlockResult.wrongPin => "That PIN didn't match. Try again.",
        UnlockResult.lockedOut => 'Too many tries. Please wait 30 seconds and try again.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biometrics = ref.watch(appLockProvider).value?.biometrics ?? false;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            const SizedBox(height: AppSpacing.xl),
            Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text('Enter your PIN', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _pin,
              autofocus: !biometrics,
              obscureText: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
              decoration: const InputDecoration(labelText: 'PIN'),
              onSubmitted: (_) => _submit(),
            ),
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_message!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _checking ? null : _submit, child: const Text('Unlock')),
            if (biometrics) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _biometrics,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Use fingerprint or face'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
