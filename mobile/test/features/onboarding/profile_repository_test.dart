import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/features/assessment/data/assessment_repository.dart';
import 'package:reclaim_app/features/assessment/domain/questionnaire.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:uuid/uuid.dart';

import '../../helpers.dart';

void main() {
  late AppDatabase db;
  late ProfileRepository profiles;

  const answers = OnboardingAnswers(
    gamblingTypes: {GamblingType.crashGame, GamblingType.sportsBetting},
    frequencyBand: FrequencyBand.weekly,
    approxMonthlySpendRands: 2500,
    triggers: {TriggerType.payday},
    goal: RecoveryGoalType.reduce,
    moneyGoalPreference: '  Car deposit ',
  );

  setUp(() {
    db = createTestDatabase();
    profiles = ProfileRepository(db, const Uuid(), () => testNow);
  });

  tearDown(() => db.close());

  test('completing onboarding creates the profile and stores the answers', () async {
    await profiles.completeOnboarding(answers);

    final profile = await profiles.watchProfile().first;
    expect(profile!.recoveryGoalType, RecoveryGoalType.reduce);
    expect(profile.startDate, DateTime(2026, 10, 29));
    expect(profile.onboardingCompletedAt, testNow);

    final response = await profiles.watchLatestOnboarding().first;
    expect(response!.gamblingTypes, [GamblingType.sportsBetting, GamblingType.crashGame]);
    expect(response.triggers, [TriggerType.payday]);
    expect(response.approxMonthlySpendRands, 2500);
    expect(response.moneyGoalPreference, 'Car deposit');
  });

  test('redoing onboarding keeps one profile and its original start date', () async {
    await profiles.completeOnboarding(answers);
    final later = ProfileRepository(db, const Uuid(), () => testNow.add(const Duration(days: 10)));
    await later.completeOnboarding(answers.copyWith(goal: RecoveryGoalType.stop, moneyGoalPreference: () => '  '));

    final all = await db.select(db.localProfiles).get();
    expect(all, hasLength(1));
    expect(all.single.recoveryGoalType, RecoveryGoalType.stop);
    expect(all.single.startDate, DateTime(2026, 10, 29));
    expect((await later.watchLatestOnboarding().first)!.moneyGoalPreference, isNull);
  });

  test('onboarding without a frequency or goal is refused', () {
    expect(() => profiles.completeOnboarding(const OnboardingAnswers()), throwsArgumentError);
  });

  test('assessment results are scored locally and kept as history', () async {
    final repo = AssessmentRepository(db, const Uuid(), () => testNow);
    final all3 = {for (final q in Questionnaire.questions) q.id: 3};
    final all0 = {for (final q in Questionnaire.questions) q.id: 0};

    final first = await repo.submit(all3);
    expect(first.score, 27);
    expect(first.riskLevel, RiskLevel.high);
    await repo.submit(all0);

    final history = await repo.watchHistory().first;
    expect(history, hasLength(2));
    expect((await repo.find(first.id))!.answers, all3);
  });
}
