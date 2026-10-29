import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/assessment/presentation/assessment_result_screen.dart';
import '../../features/assessment/presentation/assessment_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/data/profile_repository.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/shell/presentation/coming_soon_screens.dart';
import '../../features/shell/presentation/splash_screen.dart';
import '../../features/tracker/presentation/entry_form_screen.dart';

part 'app_router.g.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const onboarding = '/onboarding';
  static const assessment = '/assessment';
  static String assessmentResult(String id) => '/assessment/result/$id';
  static const newEntry = '/entries/new';
  static String editEntry(String id) => '/entries/$id';

  static const home = '/home';
  static const progress = '/progress';
  static const block = '/block';
  static const journal = '/journal';
  static const support = '/support';
}

/// Sends people who haven't finished onboarding to the welcome screen, and everyone else
/// past it.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final onboarded = ValueNotifier<AsyncValue<bool>>(const AsyncLoading());
  ref.listen(
    profileProvider,
    (_, next) => onboarded.value = next.whenData((profile) => profile?.onboardingCompletedAt != null),
    fireImmediately: true,
  );

  final router = GoRouter(
    initialLocation: Routes.home,
    refreshListenable: onboarded,
    redirect: (context, state) {
      final status = onboarded.value;
      final location = state.matchedLocation;
      if (status is! AsyncData<bool>) {
        return location == Routes.splash ? null : Routes.splash;
      }
      final inOnboarding = location == Routes.welcome || location == Routes.onboarding;
      if (!status.value) {
        return inOnboarding ? null : Routes.welcome;
      }
      return inOnboarding || location == Routes.splash ? Routes.home : null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: Routes.assessment,
        builder: (_, state) => AssessmentScreen(afterOnboarding: state.uri.queryParameters['next'] == 'home'),
        routes: [
          GoRoute(
            path: 'result/:id',
            builder: (_, state) => AssessmentResultScreen(resultId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: Routes.newEntry, builder: (_, _) => const EntryFormScreen()),
      GoRoute(path: '/entries/:id', builder: (_, state) => EntryFormScreen(entryId: state.pathParameters['id'])),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.progress, builder: (_, _) => const ProgressScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.block, builder: (_, _) => const BlockComingSoonScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.journal, builder: (_, _) => const JournalComingSoonScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.support, builder: (_, _) => const SupportComingSoonScreen())]),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    onboarded.dispose();
  });
  return router;
}
