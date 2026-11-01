import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/account/presentation/account_screen.dart';
import '../../features/assessment/presentation/assessment_result_screen.dart';
import '../../features/assessment/presentation/assessment_screen.dart';
import '../../features/blocker/presentation/block_screen.dart';
import '../../features/goals/presentation/goal_detail_screen.dart';
import '../../features/goals/presentation/goal_form_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/journal/presentation/journal_entry_screen.dart';
import '../../features/journal/presentation/journal_screen.dart';
import '../../features/onboarding/data/profile_repository.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/settings/presentation/app_lock_controller.dart';
import '../../features/settings/presentation/lock_screen.dart';
import '../../features/settings/presentation/pin_setup_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/shell/presentation/coming_soon_screens.dart';
import '../../features/shell/presentation/splash_screen.dart';
import '../../features/timeline/presentation/timeline_screen.dart';
import '../../features/tracker/presentation/entry_form_screen.dart';
import '../../features/urges/presentation/urge_session_screen.dart';
import '../../features/urges/presentation/urge_start_screen.dart';

part 'app_router.g.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const onboarding = '/onboarding';
  static const assessment = '/assessment';
  static String assessmentResult(String id) => '/assessment/result/$id';
  static const newEntry = '/entries/new';
  static String editEntry(String id) => '/entries/$id';
  static const urge = '/urge';
  static String urgeSession(String id) => '/urge/$id';
  static const goals = '/goals';
  static String newGoal({String? name}) => Uri(path: '/goals/new', queryParameters: name == null ? null : {'name': name}).toString();
  static String goal(String id) => '/goals/$id';
  static String editGoal(String id) => '/goals/$id/edit';
  static const newJournalEntry = '/journal-entries/new';
  static String journalEntry(String id) => '/journal-entries/$id';
  static const timeline = '/timeline';
  static const settings = '/settings';
  static const pinSetup = '/settings/app-lock';
  static const account = '/settings/account';
  static const lock = '/lock';

  static const home = '/home';
  static const progress = '/progress';
  static const block = '/block';
  static const journal = '/journal';
  static const support = '/support';
}

/// Sends people who haven't finished onboarding to the welcome screen, a locked app to the
/// lock screen, and everyone else past both.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final onboarded = ValueNotifier<AsyncValue<bool>>(const AsyncLoading());
  // Only whether the app is locked (null while loading): other lock-state changes, like turning
  // the lock on, must not refresh the router, which would rebuild the page stack mid-navigation.
  final locked = ValueNotifier<bool?>(null);
  ref.listen(
    profileProvider,
    (_, next) => onboarded.value = next.whenData((profile) => profile?.onboardingCompletedAt != null),
    fireImmediately: true,
  );
  ref.listen(appLockProvider, (_, next) => locked.value = next.value?.locked, fireImmediately: true);

  final router = GoRouter(
    initialLocation: Routes.home,
    refreshListenable: Listenable.merge([onboarded, locked]),
    redirect: (context, state) {
      final status = onboarded.value;
      final isLocked = locked.value;
      final location = state.matchedLocation;
      if (status is! AsyncData<bool> || isLocked == null) {
        return location == Routes.splash ? null : Routes.splash;
      }
      // Locking replaces the page stack, so unlocking starts again from Home.
      if (isLocked) return location == Routes.lock ? null : Routes.lock;
      if (location == Routes.lock) return Routes.home;

      final inOnboarding = location == Routes.welcome || location == Routes.onboarding;
      if (!status.value) {
        return inOnboarding ? null : Routes.welcome;
      }
      return inOnboarding || location == Routes.splash ? Routes.home : null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.lock, builder: (_, _) => const LockScreen()),
      GoRoute(
        path: Routes.settings,
        builder: (_, _) => const SettingsScreen(),
        routes: [
          GoRoute(path: 'app-lock', builder: (_, _) => const PinSetupScreen()),
          GoRoute(path: 'account', builder: (_, _) => const AccountScreen()),
        ],
      ),
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
      GoRoute(path: Routes.newJournalEntry, builder: (_, _) => const JournalEntryScreen()),
      GoRoute(path: '/journal-entries/:id', builder: (_, state) => JournalEntryScreen(entryId: state.pathParameters['id'])),
      GoRoute(path: Routes.timeline, builder: (_, _) => const TimelineScreen()),
      GoRoute(path: '/entries/:id', builder: (_, state) => EntryFormScreen(entryId: state.pathParameters['id'])),
      GoRoute(
        path: Routes.urge,
        builder: (_, _) => const UrgeStartScreen(),
        routes: [GoRoute(path: ':id', builder: (_, state) => UrgeSessionScreen(urgeId: state.pathParameters['id']!))],
      ),
      GoRoute(
        path: Routes.goals,
        builder: (_, _) => const GoalsScreen(),
        routes: [
          GoRoute(path: 'new', builder: (_, state) => GoalFormScreen(initialName: state.uri.queryParameters['name'])),
          GoRoute(
            path: ':id',
            builder: (_, state) => GoalDetailScreen(goalId: state.pathParameters['id']!),
            routes: [GoRoute(path: 'edit', builder: (_, state) => GoalFormScreen(goalId: state.pathParameters['id']))],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.progress, builder: (_, _) => const ProgressScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.block, builder: (_, _) => const BlockScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.journal, builder: (_, _) => const JournalScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.support, builder: (_, _) => const SupportComingSoonScreen())]),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    onboarded.dispose();
    locked.dispose();
  });
  return router;
}
