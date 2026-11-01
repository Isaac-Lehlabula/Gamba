import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/blocker/presentation/blocker_controller.dart';
import 'features/settings/presentation/app_lock_controller.dart';

class ReclaimApp extends ConsumerStatefulWidget {
  const ReclaimApp({super.key});

  @override
  ConsumerState<ReclaimApp> createState() => _ReclaimAppState();
}

class _ReclaimAppState extends ConsumerState<ReclaimApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Re-lock after time away; see AppLock.backgroundGrace.
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(appLockProvider.notifier).onBackgrounded(),
      onShow: () {
        ref.read(appLockProvider.notifier).onForegrounded();
        // Android may have stopped protection, or it may have blocked things, while away.
        ref.read(blockerProvider.notifier).refresh();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Reclaim',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(appRouterProvider),
      locale: const Locale('en', 'ZA'),
      supportedLocales: const [Locale('en', 'ZA')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
