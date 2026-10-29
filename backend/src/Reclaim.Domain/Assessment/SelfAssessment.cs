using Reclaim.Domain.Common;

namespace Reclaim.Domain.Assessment;

public enum RiskLevel
{
    Low,
    Increasing,
    High,
}

public sealed record AssessmentQuestion(string Id, string Text);

/// <summary>
/// Reclaim's own short reflection questionnaire. It is deliberately not a validated clinical
/// instrument and its result is not a diagnosis; replacing it with a licensed, validated
/// screen is a roadmap item.
/// </summary>
public static class AssessmentQuestionnaire
{
    public const int Version = 1;
    public const int MaxAnswer = 3;

    /// <summary>Answer labels, indexed by score.</summary>
    public static readonly IReadOnlyList<string> AnswerOptions = ["Never", "Sometimes", "Often", "Almost always"];

    public static readonly IReadOnlyList<AssessmentQuestion> Questions =
    [
        new("spent-more-than-planned", "In the last 3 months, how often have you spent more on gambling than you meant to?"),
        new("chased-losses", "How often have you gambled again to try to win back money you'd lost?"),
        new("needed-bigger-bets", "How often have you needed to bet more to get the same feeling?"),
        new("used-essential-money", "How often has gambling used money meant for rent, food, bills or family?"),
        new("borrowed-to-gamble", "How often have you borrowed money or sold something to gamble or cover gambling?"),
        new("kept-it-hidden", "How often have you hidden how much you gamble from people close to you?"),
        new("gambled-to-escape", "How often have you gambled to escape stress, worry or a low mood?"),
        new("hard-to-stop", "How often has it felt hard to stop or cut back when you wanted to?"),
        new("felt-bad-after", "How often have you felt guilty, anxious or low after gambling?"),
    ];

    public static int MaxScore => Questions.Count * MaxAnswer;

    /// <summary>Scores a complete set of answers. Every question must be answered exactly once.</summary>
    public static int Score(IReadOnlyDictionary<string, int> answers)
    {
        if (answers.Count != Questions.Count || Questions.Any(q => !answers.ContainsKey(q.Id)))
            throw new DomainException("Every question needs an answer.");
        if (answers.Values.Any(a => a is < 0 or > MaxAnswer))
            throw new DomainException($"Answers must be between 0 and {MaxAnswer}.");
        return answers.Values.Sum();
    }

    public static RiskLevel RiskLevelFor(int score) => score switch
    {
        <= 4 => RiskLevel.Low,
        <= 12 => RiskLevel.Increasing,
        _ => RiskLevel.High,
    };
}

/// <summary>A stored result. History is kept so change over time can be shown later.</summary>
public sealed class SelfAssessmentResult : Entity
{
    private SelfAssessmentResult() { }

    public Guid UserProfileId { get; private set; }
    public int QuestionnaireVersion { get; private set; }
    public Dictionary<string, int> Answers { get; private set; } = [];
    public int Score { get; private set; }
    public RiskLevel RiskLevel { get; private set; }

    /// <summary>Score and risk level are always computed here, never taken from the client.</summary>
    public static SelfAssessmentResult Submit(Guid? id, Guid userProfileId, IReadOnlyDictionary<string, int> answers, DateTime nowUtc)
    {
        var score = AssessmentQuestionnaire.Score(answers);
        var result = new SelfAssessmentResult
        {
            UserProfileId = userProfileId,
            QuestionnaireVersion = AssessmentQuestionnaire.Version,
            Answers = new Dictionary<string, int>(answers),
            Score = score,
            RiskLevel = AssessmentQuestionnaire.RiskLevelFor(score),
        };
        result.AssignId(id);
        result.Stamp(nowUtc);
        return result;
    }
}
