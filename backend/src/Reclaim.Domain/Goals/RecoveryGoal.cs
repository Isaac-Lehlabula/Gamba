using Reclaim.Domain.Common;

namespace Reclaim.Domain.Goals;

public enum GoalCategory
{
    EmergencyFund,
    Car,
    HouseDeposit,
    Debt,
    Holiday,
    Education,
    Family,
    Savings,
    Custom,
}

public enum ContributionSource
{
    /// <summary>Money the user says they have actually set aside.</summary>
    Manual,

    /// <summary>Part of the estimate of money kept by not gambling; always presented as an estimate.</summary>
    EstimatedSavings,
}

/// <summary>Something the user is putting money toward instead of gambling.</summary>
public sealed class RecoveryGoal : Entity
{
    public const int MaxNameLength = 60;
    public const decimal MaxAmount = 10_000_000m;

    private readonly List<GoalContribution> _contributions = [];

    private RecoveryGoal() { }

    public Guid UserProfileId { get; private set; }
    public string Name { get; private set; } = null!;
    public GoalCategory Category { get; private set; }
    public decimal TargetAmount { get; private set; }
    public DateTime? TargetDateUtc { get; private set; }

    public IReadOnlyList<GoalContribution> Contributions => _contributions;

    public decimal SavedAmount => _contributions.Sum(c => c.Amount);

    public static RecoveryGoal Create(Guid? id, Guid userProfileId, string name, GoalCategory category, decimal targetAmount, DateTime? targetDateUtc, DateTime nowUtc)
    {
        var goal = new RecoveryGoal { UserProfileId = userProfileId };
        goal.AssignId(id);
        goal.Apply(name, category, targetAmount, targetDateUtc);
        goal.Stamp(nowUtc);
        return goal;
    }

    public void Update(string name, GoalCategory category, decimal targetAmount, DateTime? targetDateUtc, DateTime nowUtc)
    {
        Apply(name, category, targetAmount, targetDateUtc);
        Touch(nowUtc);
    }

    public GoalContribution AddContribution(Guid? id, decimal amount, ContributionSource source, DateTime occurredAtUtc, DateTime nowUtc)
    {
        var contribution = GoalContribution.Create(id, Id, amount, source, occurredAtUtc, nowUtc);
        _contributions.Add(contribution);
        Touch(nowUtc);
        return contribution;
    }

    public void RemoveContribution(Guid contributionId, DateTime nowUtc)
    {
        var contribution = _contributions.FirstOrDefault(c => c.Id == contributionId)
            ?? throw new DomainException("Contribution not found on this goal.");
        _contributions.Remove(contribution);
        Touch(nowUtc);
    }

    private void Apply(string name, GoalCategory category, decimal targetAmount, DateTime? targetDateUtc)
    {
        var trimmed = name.Trim();
        if (trimmed.Length == 0 || trimmed.Length > MaxNameLength)
            throw new DomainException($"Goal name must be 1 to {MaxNameLength} characters.");
        if (targetAmount <= 0 || targetAmount > MaxAmount || decimal.Round(targetAmount, 2) != targetAmount)
            throw new DomainException("Target amount is out of range.");

        Name = trimmed;
        Category = category;
        TargetAmount = targetAmount;
        TargetDateUtc = targetDateUtc;
    }
}

public sealed class GoalContribution : Entity
{
    private GoalContribution() { }

    public Guid RecoveryGoalId { get; private set; }
    public decimal Amount { get; private set; }
    public ContributionSource Source { get; private set; }
    public DateTime OccurredAtUtc { get; private set; }

    internal static GoalContribution Create(Guid? id, Guid goalId, decimal amount, ContributionSource source, DateTime occurredAtUtc, DateTime nowUtc)
    {
        if (amount <= 0 || amount > RecoveryGoal.MaxAmount || decimal.Round(amount, 2) != amount)
            throw new DomainException("Contribution amount is out of range.");
        var contribution = new GoalContribution
        {
            RecoveryGoalId = goalId,
            Amount = amount,
            Source = source,
            OccurredAtUtc = occurredAtUtc,
        };
        contribution.AssignId(id);
        contribution.Stamp(nowUtc);
        return contribution;
    }
}
