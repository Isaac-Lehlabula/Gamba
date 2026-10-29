using Reclaim.Domain.Assessment;
using Reclaim.Domain.Gambling;
using Reclaim.Domain.Onboarding;
using Reclaim.Domain.Users;

namespace Reclaim.Application.Common.Abstractions;

public interface IAppUserRepository
{
    Task<AppUser?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>Includes accounts pending deletion, so their email cannot be re-registered mid-grace-period.</summary>
    Task<AppUser?> GetByEmailAsync(string normalizedEmail, CancellationToken cancellationToken = default);

    Task<bool> IsActiveAsync(Guid id, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<AppUser>> GetDeletedBeforeAsync(DateTime deletedBeforeUtc, int maxCount, CancellationToken cancellationToken = default);

    void Add(AppUser user);

    /// <summary>Hard-deletes the user; all owned rows cascade.</summary>
    void Remove(AppUser user);
}

public interface IRefreshTokenRepository
{
    Task<RefreshToken?> GetByHashAsync(string tokenHash, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RefreshToken>> GetUnrevokedByFamilyAsync(Guid familyId, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RefreshToken>> GetUnrevokedByUserAsync(Guid appUserId, CancellationToken cancellationToken = default);

    void Add(RefreshToken token);
}

public interface IUserProfileRepository
{
    Task<UserProfile?> GetByAppUserIdAsync(Guid appUserId, CancellationToken cancellationToken = default);

    Task<Guid?> GetIdByAppUserIdAsync(Guid appUserId, CancellationToken cancellationToken = default);

    void Add(UserProfile profile);
}

public interface IOnboardingResponseRepository
{
    Task<OnboardingResponse?> GetLatestAsync(Guid userProfileId, CancellationToken cancellationToken = default);

    Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default);

    void Add(OnboardingResponse response);
}

public interface ISelfAssessmentRepository
{
    Task<(IReadOnlyList<SelfAssessmentResult> Items, int TotalCount)> GetPageAsync(
        Guid userProfileId, int page, int pageSize, CancellationToken cancellationToken = default);

    Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default);

    void Add(SelfAssessmentResult result);
}

public sealed record GamblingEntryFilter(
    DateTime? FromUtc,
    DateTime? ToUtc,
    GamblingEntryType? EntryType,
    GamblingType? GamblingType,
    Guid? PlatformId,
    int Page,
    int PageSize);

public interface IGamblingEntryRepository
{
    /// <summary>Only returns the entry if it belongs to the profile.</summary>
    Task<GamblingEntry?> GetAsync(Guid id, Guid userProfileId, CancellationToken cancellationToken = default);

    Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>Newest first, with <see cref="GamblingEntry.Platform"/> loaded.</summary>
    Task<(IReadOnlyList<GamblingEntry> Items, int TotalCount)> QueryAsync(
        Guid userProfileId, GamblingEntryFilter filter, CancellationToken cancellationToken = default);

    /// <summary>Total amount per entry type, optionally only for entries on or after <paramref name="fromUtc"/>.</summary>
    Task<IReadOnlyDictionary<GamblingEntryType, decimal>> SumByTypeAsync(
        Guid userProfileId, DateTime? fromUtc, CancellationToken cancellationToken = default);

    void Add(GamblingEntry entry);

    void Remove(GamblingEntry entry);
}

public interface IGamblingPlatformRepository
{
    Task<GamblingPlatform?> FindAsync(Guid userProfileId, string normalizedName, CancellationToken cancellationToken = default);

    void Add(GamblingPlatform platform);
}
