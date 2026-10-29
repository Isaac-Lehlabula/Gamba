import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class ReclaimApp extends ConsumerWidget {
  const ReclaimApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
