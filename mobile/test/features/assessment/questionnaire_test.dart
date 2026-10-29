import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/features/assessment/domain/questionnaire.dart';

Map<String, int> answersTotalling(int total) {
  final answers = <String, int>{};
  for (final q in Questionnaire.questions) {
    final take = total.clamp(0, Questionnaire.maxAnswer);
    answers[q.id] = take;
    total -= take;
  }
  return answers;
}

void main() {
  test('question ids and version match the backend questionnaire', () {
    // Must stay identical to backend/src/Reclaim.Domain/Assessment/SelfAssessment.cs.
    expect(Questionnaire.version, 1);
    expect(Questionnaire.questions.map((q) => q.id), [
      'spent-more-than-planned',
      'chased-losses',
      'needed-bigger-bets',
      'used-essential-money',
      'borrowed-to-gamble',
      'kept-it-hidden',
      'gambled-to-escape',
      'hard-to-stop',
      'felt-bad-after',
    ]);
    expect(Questionnaire.maxScore, 27);
  });

  test('score boundaries match the backend', () {
    final cases = {0: RiskLevel.low, 4: RiskLevel.low, 5: RiskLevel.increasing, 12: RiskLevel.increasing, 13: RiskLevel.high, 27: RiskLevel.high};
    cases.forEach((total, level) {
      final score = Questionnaire.score(answersTotalling(total));
      expect(score, total);
      expect(Questionnaire.riskLevelFor(score), level, reason: 'score $total');
    });
  });

  test('incomplete or out-of-range answers are rejected', () {
    final missing = answersTotalling(3)..remove('chased-losses');
    expect(() => Questionnaire.score(missing), throwsArgumentError);
    expect(() => Questionnaire.score(answersTotalling(0)..['chased-losses'] = 4), throwsArgumentError);
  });

  test('guidance never uses shaming language', () {
    for (final level in RiskLevel.values) {
      final guidance = Questionnaire.guidanceFor(level);
      expect(guidance.actions, isNotEmpty);
      final text = [guidance.summary, for (final a in guidance.actions) ...[a.title, a.description]].join(' ').toLowerCase();
      expect(text, isNot(contains('addict')));
      expect(text, isNot(contains('fail')));
    }
  });
}
