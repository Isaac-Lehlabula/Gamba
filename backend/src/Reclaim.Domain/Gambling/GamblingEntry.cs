using Reclaim.Domain.Common;

namespace Reclaim.Domain.Gambling;

public enum GamblingType
{
    SportsBetting,
    Casino,
    Slots,
    CrashGame,
    Lottery,
    Other,
}

public enum GamblingEntryType
{
    Deposit,
    Withdrawal,
    Win,
    Loss,
}

/// <summary>A self-reported money movement or outcome. Wins are recorded, never celebrated.</summary>
public sealed class GamblingEntry : Entity
{
    public const decimal MaxAmount = 10_000_000m;
    public const int MaxNotesLength = 1000;

    /// <summary>Allowance for clock differences between the phone and the server.</summary>
    public static readonly TimeSpan FutureTolerance = TimeSpan.FromMinutes(10);

    private GamblingEntry() { }

    public Guid UserProfileId { get; private set; }
    public GamblingEntryType EntryType { get; private set; }
    public decimal Amount { get; private set; }

    /// <summary>When the user says it happened, which is often not when they logged it.</summary>
    public DateTime OccurredAtUtc { get; private set; }

    public GamblingType GamblingType { get; private set; }
    public Guid? GamblingPlatformId { get; private set; }
    public GamblingPlatform? Platform { get; private set; }
    public string? Notes { get; private set; }

    public static GamblingEntry Create(
        Guid? id,
        Guid userProfileId,
        GamblingEntryType entryType,
        decimal amount,
        DateTime occurredAtUtc,
        GamblingType gamblingType,
        GamblingPlatform? platform,
        string? notes,
        DateTime nowUtc)
    {
        var entry = new GamblingEntry { UserProfileId = userProfileId };
        entry.AssignId(id);
        entry.Apply(entryType, amount, occurredAtUtc, gamblingType, platform, notes, nowUtc);
        entry.Stamp(nowUtc);
        return entry;
    }

    public void Update(
        GamblingEntryType entryType,
        decimal amount,
        DateTime occurredAtUtc,
        GamblingType gamblingType,
        GamblingPlatform? platform,
        string? notes,
        DateTime nowUtc)
    {
        Apply(entryType, amount, occurredAtUtc, gamblingType, platform, notes, nowUtc);
        Touch(nowUtc);
    }

    private void Apply(
        GamblingEntryType entryType,
        decimal amount,
        DateTime occurredAtUtc,
        GamblingType gamblingType,
        GamblingPlatform? platform,
        string? notes,
        DateTime nowUtc)
    {
        if (amount <= 0 || amount > MaxAmount)
            throw new DomainException($"Amount must be more than R0 and at most R{MaxAmount:N0}.");
        if (decimal.Round(amount, 2) != amount)
            throw new DomainException("Amount can have at most two decimal places.");
        if (occurredAtUtc > nowUtc + FutureTolerance)
            throw new DomainException("An entry cannot be dated in the future.");
        if (platform is not null && platform.CreatedByUserProfileId is { } owner && owner != UserProfileId)
            throw new DomainException("Platform belongs to a different profile.");

        var trimmedNotes = string.IsNullOrWhiteSpace(notes) ? null : notes.Trim();
        if (trimmedNotes is { Length: > MaxNotesLength })
            throw new DomainException($"Notes must be at most {MaxNotesLength} characters.");

        EntryType = entryType;
        Amount = amount;
        OccurredAtUtc = occurredAtUtc;
        GamblingType = gamblingType;
        Platform = platform;
        GamblingPlatformId = platform?.Id;
        Notes = trimmedNotes;
    }
}

/// <summary>
/// A platform name the user typed, kept only so the tracker can group and autocomplete.
/// This is not a directory of gambling sites.
/// </summary>
public sealed class GamblingPlatform : Entity
{
    public const int MaxNameLength = 80;

    private GamblingPlatform() { }

    public string Name { get; private set; } = null!;

    /// <summary>Case-insensitive key, so "Betway" and "betway " are the same platform.</summary>
    public string NormalizedName { get; private set; } = null!;

    /// <summary>Null only for commonly used names seeded by the backend.</summary>
    public Guid? CreatedByUserProfileId { get; private set; }

    public static string Normalize(string name) => name.Trim().ToUpperInvariant();

    public static GamblingPlatform CreateForProfile(Guid userProfileId, string name, DateTime nowUtc)
    {
        var trimmed = name.Trim();
        if (trimmed.Length == 0 || trimmed.Length > MaxNameLength)
            throw new DomainException($"Platform name must be 1 to {MaxNameLength} characters.");

        var platform = new GamblingPlatform
        {
            Name = trimmed,
            NormalizedName = Normalize(trimmed),
            CreatedByUserProfileId = userProfileId,
        };
        platform.Stamp(nowUtc);
        return platform;
    }
}
