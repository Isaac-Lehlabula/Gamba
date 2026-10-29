using Reclaim.Domain.Common;

namespace Reclaim.Domain.Users;

/// <summary>
/// The backend copy of a user's profile. Only exists for accounts; anonymous users have a
/// purely on-device profile identified by <see cref="LocalProfileId"/>.
/// </summary>
public sealed class UserProfile : Entity
{
    public const int MaxDisplayNameLength = 60;

    private UserProfile() { }

    public Guid? AppUserId { get; private set; }

    /// <summary>The on-device identifier, kept so a local profile maps onto its synced copy.</summary>
    public Guid LocalProfileId { get; private set; }

    public string? DisplayName { get; private set; }
    public RecoveryGoalType? RecoveryGoalType { get; private set; }
    public DateTime? QuitOrReductionStartDateUtc { get; private set; }

    public static UserProfile CreateForAccount(Guid appUserId, Guid? localProfileId, DateTime nowUtc)
    {
        var profile = new UserProfile
        {
            AppUserId = appUserId,
            LocalProfileId = localProfileId is { } id && id != Guid.Empty ? id : Guid.NewGuid(),
        };
        profile.Stamp(nowUtc);
        return profile;
    }

    public void Update(string? displayName, RecoveryGoalType? recoveryGoalType, DateTime? quitOrReductionStartDateUtc, DateTime nowUtc)
    {
        var trimmed = string.IsNullOrWhiteSpace(displayName) ? null : displayName.Trim();
        if (trimmed is { Length: > MaxDisplayNameLength })
            throw new DomainException($"Display name must be at most {MaxDisplayNameLength} characters.");
        if (quitOrReductionStartDateUtc > nowUtc)
            throw new DomainException("Start date cannot be in the future.");

        DisplayName = trimmed;
        RecoveryGoalType = recoveryGoalType;
        QuitOrReductionStartDateUtc = quitOrReductionStartDateUtc;
        Touch(nowUtc);
    }
}
