using FluentValidation;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Assessment;

namespace Reclaim.Application.Assessment;

public sealed record AnswerOption(int Value, string Label);

public sealed record QuestionnaireResponse(
    int Version,
    IReadOnlyList<AssessmentQuestion> Questions,
    IReadOnlyList<AnswerOption> AnswerOptions,
    string Disclaimer);

public sealed record SubmitAssessmentRequest(Guid? Id, Dictionary<string, int>? Answers);

public sealed record RecommendedAction(string Code, string Title, string Description);

public sealed record AssessmentResultResponse(
    Guid Id,
    int Score,
    int MaxScore,
    RiskLevel RiskLevel,
    string Summary,
    IReadOnlyList<RecommendedAction> RecommendedActions,
    string Disclaimer,
    DateTime CreatedAtUtc)
{
    public static AssessmentResultResponse From(SelfAssessmentResult r)
    {
        var guidance = AssessmentGuidance.For(r.RiskLevel);
        return new(r.Id, r.Score, AssessmentQuestionnaire.MaxScore, r.RiskLevel, guidance.Summary, guidance.Actions,
            AssessmentGuidance.Disclaimer, r.CreatedAtUtc);
    }
}

/// <summary>
/// What a result means and what to do next. Written to be calm and never shaming: the user
/// may be reading this at a very low point.
/// </summary>
public static class AssessmentGuidance
{
    public const string Disclaimer =
        "This is a reflection tool, not a medical diagnosis. For a fuller picture, speak to a counsellor or healthcare professional.";

    private static readonly RecommendedAction TrackSpending = new("TrackSpending", "Keep track of what you spend",
        "Logging deposits and withdrawals makes the real cost easier to see.");
    private static readonly RecommendedAction SetGoal = new("SetGoal", "Choose something to put money toward",
        "A goal you care about gives every rand you keep somewhere to go.");
    private static readonly RecommendedAction Reassess = new("Reassess", "Check in again in a month",
        "Answering again later shows how things are changing.");
    private static readonly RecommendedAction EnableBlocking = new("EnableBlocking", "Block gambling sites on this phone",
        "Putting a barrier between an urge and a bet gives you time to choose.");
    private static readonly RecommendedAction UseUrgeTool = new("UseUrgeTool", "Use \"I feel like gambling\" when an urge hits",
        "A short cooling-off pause helps most urges pass.");
    private static readonly RecommendedAction TalkToSomeone = new("TalkToSomeone", "Talk to someone you trust",
        "Saying it out loud to one person can take a lot of the weight off.");
    private static readonly RecommendedAction ProtectionLock = new("ProtectionLock", "Lock your protection in place",
        "A protection lock stops blocking being switched off in a difficult moment.");
    private static readonly RecommendedAction SpeakToProfessional = new("SpeakToProfessional", "Speak to a counsellor or support line",
        "Confidential support is available, and many people find it makes a real difference.");
    private static readonly RecommendedAction FinancialSupport = new("FinancialSupport", "Get help with money pressure",
        "A financial counsellor can help with debt and a plan to get back on track.");

    public static (string Summary, IReadOnlyList<RecommendedAction> Actions) For(RiskLevel level) => level switch
    {
        RiskLevel.Low => (
            "Your answers suggest gambling isn't causing you much harm right now. It can still help to keep an eye on it.",
            [TrackSpending, SetGoal, Reassess]),
        RiskLevel.Increasing => (
            "Your answers suggest gambling may be starting to cost you more than you'd like. This is a good moment to put some protection in place.",
            [TrackSpending, EnableBlocking, UseUrgeTool, TalkToSomeone]),
        RiskLevel.High => (
            "Your answers suggest gambling is causing you real harm right now. You don't have to handle this alone, and things can get better.",
            [EnableBlocking, ProtectionLock, SpeakToProfessional, FinancialSupport, UseUrgeTool]),
        _ => throw new ArgumentOutOfRangeException(nameof(level)),
    };
}

public sealed class SubmitAssessmentRequestValidator : AbstractValidator<SubmitAssessmentRequest>
{
    public SubmitAssessmentRequestValidator()
    {
        RuleFor(x => x.Answers).NotNull()
            .Must(a => a!.Count == AssessmentQuestionnaire.Questions.Count && AssessmentQuestionnaire.Questions.All(q => a.ContainsKey(q.Id)))
            .WithMessage("Every question needs exactly one answer.")
            .When(x => x.Answers is not null);
        RuleForEach(x => x.Answers).Must(a => a.Value is >= 0 and <= AssessmentQuestionnaire.MaxAnswer)
            .WithMessage($"Answers must be between 0 and {AssessmentQuestionnaire.MaxAnswer}.");
    }
}

public sealed class GetQuestionnaireHandler
{
    public QuestionnaireResponse Handle() => new(
        AssessmentQuestionnaire.Version,
        AssessmentQuestionnaire.Questions,
        AssessmentQuestionnaire.AnswerOptions.Select((label, value) => new AnswerOption(value, label)).ToList(),
        AssessmentGuidance.Disclaimer);
}

public sealed class SubmitAssessmentHandler(
    IUserProfileRepository profiles,
    ISelfAssessmentRepository results,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    public async Task<AssessmentResultResponse> HandleAsync(Guid appUserId, SubmitAssessmentRequest request, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        if (request.Id is { } id && await results.ExistsAsync(id, cancellationToken))
            throw new ConflictException("An assessment with this id already exists.");

        var result = SelfAssessmentResult.Submit(request.Id, profileId, request.Answers!, time.GetUtcNow().UtcDateTime);
        results.Add(result);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return AssessmentResultResponse.From(result);
    }
}

public sealed class GetAssessmentHistoryHandler(IUserProfileRepository profiles, ISelfAssessmentRepository results)
{
    public async Task<PagedResponse<AssessmentResultResponse>> HandleAsync(Guid appUserId, int page, int pageSize, CancellationToken cancellationToken = default)
    {
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, Paging.MaxPageSize);
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        var (items, total) = await results.GetPageAsync(profileId, page, pageSize, cancellationToken);
        return new(items.Select(AssessmentResultResponse.From).ToList(), page, pageSize, total);
    }
}
