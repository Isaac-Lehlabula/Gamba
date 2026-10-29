// Mirrors backend/src/Reclaim.Domain/Assessment/SelfAssessment.cs (questionnaire version 1).
// The app scores offline; the backend re-scores on sync and never trusts these numbers.
// Question ids and thresholds must stay identical; questionnaire_test.dart pins them.

enum RiskLevel {
  low('Low concern'),
  increasing('Increasing risk'),
  high('High risk');

  const RiskLevel(this.label);
  final String label;
}

class AssessmentQuestion {
  const AssessmentQuestion(this.id, this.text);
  final String id;
  final String text;
}

class RecommendedAction {
  const RecommendedAction(this.code, this.title, this.description);
  final String code;
  final String title;
  final String description;
}

class AssessmentGuidance {
  const AssessmentGuidance(this.summary, this.actions);
  final String summary;
  final List<RecommendedAction> actions;
}

abstract final class Questionnaire {
  static const version = 1;
  static const maxAnswer = 3;

  static const answerOptions = ['Never', 'Sometimes', 'Often', 'Almost always'];

  static const questions = [
    AssessmentQuestion('spent-more-than-planned', 'In the last 3 months, how often have you spent more on gambling than you meant to?'),
    AssessmentQuestion('chased-losses', "How often have you gambled again to try to win back money you'd lost?"),
    AssessmentQuestion('needed-bigger-bets', 'How often have you needed to bet more to get the same feeling?'),
    AssessmentQuestion('used-essential-money', 'How often has gambling used money meant for rent, food, bills or family?'),
    AssessmentQuestion('borrowed-to-gamble', 'How often have you borrowed money or sold something to gamble or cover gambling?'),
    AssessmentQuestion('kept-it-hidden', 'How often have you hidden how much you gamble from people close to you?'),
    AssessmentQuestion('gambled-to-escape', 'How often have you gambled to escape stress, worry or a low mood?'),
    AssessmentQuestion('hard-to-stop', 'How often has it felt hard to stop or cut back when you wanted to?'),
    AssessmentQuestion('felt-bad-after', 'How often have you felt guilty, anxious or low after gambling?'),
  ];

  static int get maxScore => questions.length * maxAnswer;

  static const disclaimer =
      'This is a reflection tool, not a medical diagnosis. For a fuller picture, speak to a counsellor or healthcare professional.';

  /// Every question must be answered exactly once, with a value from 0 to [maxAnswer].
  static int score(Map<String, int> answers) {
    if (answers.length != questions.length || questions.any((q) => !answers.containsKey(q.id))) {
      throw ArgumentError('Every question needs an answer.');
    }
    if (answers.values.any((a) => a < 0 || a > maxAnswer)) {
      throw ArgumentError('Answers must be between 0 and $maxAnswer.');
    }
    return answers.values.fold(0, (sum, a) => sum + a);
  }

  static RiskLevel riskLevelFor(int score) => switch (score) {
        <= 4 => RiskLevel.low,
        <= 12 => RiskLevel.increasing,
        _ => RiskLevel.high,
      };

  static const _trackSpending = RecommendedAction('TrackSpending', 'Keep track of what you spend',
      'Logging deposits and withdrawals makes the real cost easier to see.');
  static const _setGoal = RecommendedAction('SetGoal', 'Choose something to put money toward',
      'A goal you care about gives every rand you keep somewhere to go.');
  static const _reassess =
      RecommendedAction('Reassess', 'Check in again in a month', 'Answering again later shows how things are changing.');
  static const _enableBlocking = RecommendedAction('EnableBlocking', 'Block gambling sites on this phone',
      'Putting a barrier between an urge and a bet gives you time to choose.');
  static const _useUrgeTool = RecommendedAction('UseUrgeTool', 'Use "I feel like gambling" when an urge hits',
      'A short cooling-off pause helps most urges pass.');
  static const _talkToSomeone = RecommendedAction('TalkToSomeone', 'Talk to someone you trust',
      'Saying it out loud to one person can take a lot of the weight off.');
  static const _protectionLock = RecommendedAction('ProtectionLock', 'Lock your protection in place',
      'A protection lock stops blocking being switched off in a difficult moment.');
  static const _speakToProfessional = RecommendedAction('SpeakToProfessional', 'Speak to a counsellor or support line',
      'Free, confidential support is available, and many people find it makes a real difference.');
  static const _financialSupport = RecommendedAction('FinancialSupport', 'Get help with money pressure',
      'A financial counsellor can help with debt and a plan to get back on track.');

  static AssessmentGuidance guidanceFor(RiskLevel level) => switch (level) {
        RiskLevel.low => const AssessmentGuidance(
            "Your answers suggest gambling isn't causing you much harm right now. It can still help to keep an eye on it.",
            [_trackSpending, _setGoal, _reassess],
          ),
        RiskLevel.increasing => const AssessmentGuidance(
            "Your answers suggest gambling may be starting to cost you more than you'd like. This is a good moment to put some protection in place.",
            [_trackSpending, _enableBlocking, _useUrgeTool, _talkToSomeone],
          ),
        RiskLevel.high => const AssessmentGuidance(
            "Your answers suggest gambling is causing you real harm right now. You don't have to handle this alone, and things can get better.",
            [_enableBlocking, _protectionLock, _speakToProfessional, _financialSupport, _useUrgeTool],
          ),
      };
}
