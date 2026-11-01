import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../domain/onboarding_models.dart';

part 'profile_repository.g.dart';

/// Owns the single local profile and the onboarding answers that create it.
class ProfileRepository {
  ProfileRepository(this._db, this._uuid, this._now);

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _now;

  Stream<LocalProfile?> watchProfile() => _db.select(_db.localProfiles).watchSingleOrNull();

  Stream<OnboardingResponse?> watchLatestOnboarding() => (_db.select(_db.onboardingResponses)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(1))
      .watchSingleOrNull();

  /// Saves the answers and creates (or updates) the profile, marking onboarding complete.
  /// Today is taken as the start of the user's journey.
  Future<void> completeOnboarding(OnboardingAnswers answers) {
    if (!answers.isComplete) {
      throw ArgumentError('Onboarding needs a frequency and a goal.');
    }
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final moneyGoal = answers.moneyGoalPreference?.trim();

    return _db.transaction(() async {
      await _db.into(_db.onboardingResponses).insert(
            OnboardingResponsesCompanion.insert(
              id: _uuid.v4(),
              gamblingTypes: GamblingType.values.where(answers.gamblingTypes.contains).toList(),
              frequencyBand: answers.frequencyBand!,
              approxMonthlySpendRands: Value(answers.approxMonthlySpendRands),
              triggers: TriggerType.values.where(answers.triggers.contains).toList(),
              goal: answers.goal!,
              moneyGoalPreference: Value(moneyGoal == null || moneyGoal.isEmpty ? null : moneyGoal),
              createdAt: now,
            ),
          );

      final existing = await _db.select(_db.localProfiles).getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.localProfiles).insert(
              LocalProfilesCompanion.insert(
                id: _uuid.v4(),
                recoveryGoalType: Value(answers.goal),
                startDate: Value(today),
                onboardingCompletedAt: Value(now),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (_db.update(_db.localProfiles)..where((t) => t.id.equals(existing.id))).write(
          LocalProfilesCompanion(
            recoveryGoalType: Value(answers.goal),
            startDate: Value(existing.startDate ?? today),
            onboardingCompletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }
}

extension PlanEdits on ProfileRepository {
  Future<void> setGoalType(RecoveryGoalType goal) =>
      _db.update(_db.localProfiles).write(LocalProfilesCompanion(recoveryGoalType: Value(goal), updatedAt: Value(_now())));

  /// Updates the usual monthly spend used for the money-kept estimate. It lives on the latest
  /// onboarding answers, which is where it was first given.
  Future<void> setUsualMonthlySpend(int? rands) async {
    if (rands != null && rands < 0) throw ArgumentError('Spend cannot be negative.');
    final latest = await (_db.select(_db.onboardingResponses)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (latest == null) return;
    await (_db.update(_db.onboardingResponses)..where((t) => t.id.equals(latest.id)))
        .write(OnboardingResponsesCompanion(approxMonthlySpendRands: Value(rands)));
  }
}

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) =>
    ProfileRepository(ref.watch(appDatabaseProvider), ref.watch(uuidProvider), ref.watch(clockProvider));

@Riverpod(keepAlive: true)
Stream<LocalProfile?> profile(Ref ref) => ref.watch(profileRepositoryProvider).watchProfile();

@riverpod
Stream<OnboardingResponse?> latestOnboarding(Ref ref) => ref.watch(profileRepositoryProvider).watchLatestOnboarding();
