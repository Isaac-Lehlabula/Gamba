using Reclaim.Domain.Common;
using Reclaim.Domain.Onboarding;

namespace Reclaim.Domain.Urges;

public enum UrgeOutcome
{
    Passed,
    Gambled,
    Abandoned,
}

/// <summary>One "I feel like gambling" session: the trigger, the pause chosen, and how it ended.</summary>
public sealed class Urge : Entity
{
    public static readonly IReadOnlySet<int> PauseOptions = new HashSet<int> { 10, 20, 30, 60 };
    public const int ExtensionMinutes = 10;
    public const int MaxCoolingOffMinutes = 24 * 60;
    public const int MaxNotesLength = 1000;

    private Urge() { }

    public Guid UserProfileId { get; private set; }
    public TriggerType Trigger { get; private set; }
    public int? Intensity { get; private set; }
    public int CoolingOffMinutes { get; private set; }
    public DateTime StartedAtUtc { get; private set; }
    public DateTime? ResolvedAtUtc { get; private set; }
    public UrgeOutcome? Outcome { get; private set; }
    public string? Notes { get; private set; }

    public bool IsResolved => Outcome is not null;

    public static Urge Start(Guid? id, Guid userProfileId, TriggerType trigger, int? intensity, int coolingOffMinutes, DateTime startedAtUtc, DateTime nowUtc)
    {
        if (!PauseOptions.Contains(coolingOffMinutes))
            throw new DomainException("Pause must be 10, 20, 30 or 60 minutes.");
        if (intensity is < 1 or > 5)
            throw new DomainException("Intensity must be between 1 and 5.");
        if (startedAtUtc > nowUtc + TimeSpan.FromMinutes(10))
            throw new DomainException("An urge cannot start in the future.");

        var urge = new Urge
        {
            UserProfileId = userProfileId,
            Trigger = trigger,
            Intensity = intensity,
            CoolingOffMinutes = coolingOffMinutes,
            StartedAtUtc = startedAtUtc,
        };
        urge.AssignId(id);
        urge.Stamp(nowUtc);
        return urge;
    }

    /// <summary>Adds more time to an unresolved pause.</summary>
    public void Extend(DateTime nowUtc)
    {
        if (IsResolved) throw new DomainException("This urge has already been resolved.");
        if (CoolingOffMinutes + ExtensionMinutes > MaxCoolingOffMinutes) throw new DomainException("The pause cannot be extended further.");
        CoolingOffMinutes += ExtensionMinutes;
        Touch(nowUtc);
    }

    public void Resolve(UrgeOutcome outcome, string? notes, DateTime resolvedAtUtc, DateTime nowUtc)
    {
        if (IsResolved) throw new DomainException("This urge has already been resolved.");
        if (resolvedAtUtc < StartedAtUtc) throw new DomainException("An urge cannot end before it started.");
        var trimmed = string.IsNullOrWhiteSpace(notes) ? null : notes.Trim();
        if (trimmed is { Length: > MaxNotesLength }) throw new DomainException($"Notes must be at most {MaxNotesLength} characters.");

        Outcome = outcome;
        ResolvedAtUtc = resolvedAtUtc;
        Notes = trimmed;
        Touch(nowUtc);
    }
}
