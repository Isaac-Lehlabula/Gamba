using Reclaim.Domain.Common;
using Reclaim.Domain.Onboarding;

namespace Reclaim.Domain.Journal;

public enum JournalOutcome
{
    NoUrge,
    Resisted,
    Gambled,
}

/// <summary>What helped (or what the user tried) when an urge came up.</summary>
public enum CopingStrategy
{
    Walked,
    TalkedToSomeone,
    Breathing,
    Distraction,
    BlockedSites,
    LeftPhone,
    RememberedGoal,
    Other,
}

/// <summary>A private journal entry: mood, an urge if there was one, and what helped.</summary>
public sealed class JournalEntry : Entity
{
    public const int MaxNoteLength = 2000;

    private JournalEntry() { }

    public Guid UserProfileId { get; private set; }
    public DateTime OccurredAtUtc { get; private set; }
    public int? Mood { get; private set; }
    public TriggerType? Trigger { get; private set; }
    public int? UrgeIntensity { get; private set; }
    public JournalOutcome? Outcome { get; private set; }
    public List<CopingStrategy> Helped { get; private set; } = [];
    public string? Note { get; private set; }

    /// <summary>Whether this entry records an urge (for insights).</summary>
    public bool HadUrge => UrgeIntensity is not null || Outcome is JournalOutcome.Resisted or JournalOutcome.Gambled;

    public static JournalEntry Create(
        Guid? id, Guid userProfileId, DateTime occurredAtUtc, int? mood, TriggerType? trigger, int? urgeIntensity,
        JournalOutcome? outcome, IEnumerable<CopingStrategy> helped, string? note, DateTime nowUtc)
    {
        var entry = new JournalEntry { UserProfileId = userProfileId };
        entry.AssignId(id);
        entry.Apply(occurredAtUtc, mood, trigger, urgeIntensity, outcome, helped, note, nowUtc);
        entry.Stamp(nowUtc);
        return entry;
    }

    public void Update(
        DateTime occurredAtUtc, int? mood, TriggerType? trigger, int? urgeIntensity,
        JournalOutcome? outcome, IEnumerable<CopingStrategy> helped, string? note, DateTime nowUtc)
    {
        Apply(occurredAtUtc, mood, trigger, urgeIntensity, outcome, helped, note, nowUtc);
        Touch(nowUtc);
    }

    private void Apply(
        DateTime occurredAtUtc, int? mood, TriggerType? trigger, int? urgeIntensity,
        JournalOutcome? outcome, IEnumerable<CopingStrategy> helped, string? note, DateTime nowUtc)
    {
        if (mood is < 1 or > 5 || urgeIntensity is < 1 or > 5)
            throw new DomainException("Scales run from 1 to 5.");
        if (occurredAtUtc > nowUtc + TimeSpan.FromMinutes(10))
            throw new DomainException("An entry cannot be dated in the future.");
        var trimmed = string.IsNullOrWhiteSpace(note) ? null : note.Trim();
        if (trimmed is { Length: > MaxNoteLength })
            throw new DomainException($"Note must be at most {MaxNoteLength} characters.");
        var helpedList = helped.Distinct().Order().ToList();
        if (mood is null && trigger is null && urgeIntensity is null && outcome is null && helpedList.Count == 0 && trimmed is null)
            throw new DomainException("A journal entry needs something in it.");

        OccurredAtUtc = occurredAtUtc;
        Mood = mood;
        Trigger = trigger;
        UrgeIntensity = urgeIntensity;
        Outcome = outcome;
        Helped = helpedList;
        Note = trimmed;
    }
}
