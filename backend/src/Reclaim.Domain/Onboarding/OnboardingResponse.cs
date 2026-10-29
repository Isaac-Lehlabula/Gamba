using Reclaim.Domain.Common;
using Reclaim.Domain.Gambling;
using Reclaim.Domain.Users;

namespace Reclaim.Domain.Onboarding;

public enum FrequencyBand
{
    LessThanMonthly,
    Monthly,
    Weekly,
    SeveralTimesAWeek,
    Daily,
}

/// <summary>What tends to come before an urge. Shared by onboarding and the urge flow.</summary>
public enum TriggerType
{
    Stress,
    Boredom,
    Payday,
    TryingToRecoverLosses,
    Alcohol,
    FriendsGambling,
    Loneliness,
    Excitement,
    FinancialPressure,
    Other,
}

/// <summary>One submission of the onboarding questionnaire. Resubmitting adds a new row.</summary>
public sealed class OnboardingResponse : Entity
{
    public const int MaxMoneyGoalPreferenceLength = 200;
    public const decimal MaxMonthlySpend = 10_000_000m;

    private OnboardingResponse() { }

    public Guid UserProfileId { get; private set; }
    public List<GamblingType> GamblingTypes { get; private set; } = [];
    public FrequencyBand FrequencyBand { get; private set; }
    public decimal? ApproxMonthlySpend { get; private set; }
    public List<TriggerType> Triggers { get; private set; } = [];
    public RecoveryGoalType Goal { get; private set; }

    /// <summary>What the user would rather put the money toward, in their own words.</summary>
    public string? MoneyGoalPreference { get; private set; }

    public static OnboardingResponse Create(
        Guid? id,
        Guid userProfileId,
        IEnumerable<GamblingType> gamblingTypes,
        FrequencyBand frequencyBand,
        decimal? approxMonthlySpend,
        IEnumerable<TriggerType> triggers,
        RecoveryGoalType goal,
        string? moneyGoalPreference,
        DateTime nowUtc)
    {
        if (approxMonthlySpend is < 0 or > MaxMonthlySpend)
            throw new DomainException("Monthly spend is out of range.");

        var preference = string.IsNullOrWhiteSpace(moneyGoalPreference) ? null : moneyGoalPreference.Trim();
        if (preference is { Length: > MaxMoneyGoalPreferenceLength })
            throw new DomainException($"Money goal must be at most {MaxMoneyGoalPreferenceLength} characters.");

        var response = new OnboardingResponse
        {
            UserProfileId = userProfileId,
            GamblingTypes = gamblingTypes.Distinct().ToList(),
            FrequencyBand = frequencyBand,
            ApproxMonthlySpend = approxMonthlySpend,
            Triggers = triggers.Distinct().ToList(),
            Goal = goal,
            MoneyGoalPreference = preference,
        };
        response.AssignId(id);
        response.Stamp(nowUtc);
        return response;
    }
}
