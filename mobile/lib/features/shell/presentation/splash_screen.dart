import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../onboarding/data/profile_repository.dart';

/// Shown while the encrypted database opens.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: AppSpacing.screen,
          child: profile.hasError
              ? const Text(
                  "Reclaim couldn't open your data on this phone. Please close the app and try again.",
                  textAlign: TextAlign.center,
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
