import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/app_lock_repository.dart';
import '../domain/pin_hasher.dart';
import 'app_lock_controller.dart';

/// Choose a PIN (entered twice) and, where the phone supports it, biometric unlock.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _biometrics = false;
  bool _saving = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref.read(appLockProvider.notifier).enable(_pin.text, biometrics: _biometrics);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biometricsAvailable = ref.watch(_biometricsAvailableProvider).value ?? false;

    InputDecoration field(String label) => InputDecoration(labelText: label, counterText: '');

    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: AppSpacing.screen,
            children: [
              Text(
                'Reclaim will ask for this PIN when it opens, so no one else using your phone can see inside.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _pin,
                obscureText: true,
                maxLength: 8,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: field('Choose a PIN (4 to 8 digits)'),
                validator: (pin) => PinHasher.isValidPin(pin ?? '') ? null : 'Use 4 to 8 digits',
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                maxLength: 8,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: field('Enter it again'),
                validator: (pin) => pin == _pin.text ? null : "The PINs don't match",
              ),
              if (biometricsAvailable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Also unlock with fingerprint or face'),
                  value: _biometrics,
                  onChanged: (v) => setState(() => _biometrics = v),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "If you forget your PIN, the only way back in is to reinstall Reclaim, which deletes what's stored on this phone.",
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Turn on app lock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _biometricsAvailableProvider = FutureProvider.autoDispose<bool>((ref) => ref.watch(biometricAuthProvider).isAvailable());
