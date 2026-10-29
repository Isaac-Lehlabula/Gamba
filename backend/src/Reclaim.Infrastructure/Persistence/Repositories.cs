using Microsoft.EntityFrameworkCore;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Assessment;
using Reclaim.Domain.Gambling;
using Reclaim.Domain.Onboarding;
using Reclaim.Domain.Users;

namespace Reclaim.Infrastructure.Persistence;

internal sealed class AppUserRepository(ReclaimDbContext db) : IAppUserRepository
{
    public Task<AppUser?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.AppUsers.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);

    public Task<AppUser?> GetByEmailAsync(string normalizedEmail, CancellationToken cancellationToken = default) =>
        db.AppUsers.FirstOrDefaultAsync(x => x.Email == normalizedEmail, cancellationToken);

    public Task<bool> IsActiveAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.AppUsers.AnyAsync(x => x.Id == id && x.DeletedAtUtc == null, cancellationToken);

    public async Task<IReadOnlyList<AppUser>> GetDeletedBeforeAsync(DateTime deletedBeforeUtc, int maxCount, CancellationToken cancellationToken = default) =>
        await db.AppUsers
            .Where(x => x.DeletedAtUtc != null && x.DeletedAtUtc < deletedBeforeUtc)
            .OrderBy(x => x.DeletedAtUtc)
            .Take(maxCount)
            .ToListAsync(cancellationToken);

    public void Add(AppUser user) => db.AppUsers.Add(user);

    public void Remove(AppUser user) => db.AppUsers.Remove(user);
}

internal sealed class RefreshTokenRepository(ReclaimDbContext db) : IRefreshTokenRepository
{
    public Task<RefreshToken?> GetByHashAsync(string tokenHash, CancellationToken cancellationToken = default) =>
        db.RefreshTokens.FirstOrDefaultAsync(x => x.TokenHash == tokenHash, cancellationToken);

    public async Task<IReadOnlyList<RefreshToken>> GetUnrevokedByFamilyAsync(Guid familyId, CancellationToken cancellationToken = default) =>
        await db.RefreshTokens.Where(x => x.FamilyId == familyId && x.RevokedAtUtc == null).ToListAsync(cancellationToken);

    public async Task<IReadOnlyList<RefreshToken>> GetUnrevokedByUserAsync(Guid appUserId, CancellationToken cancellationToken = default) =>
        await db.RefreshTokens.Where(x => x.AppUserId == appUserId && x.RevokedAtUtc == null).ToListAsync(cancellationToken);

    public void Add(RefreshToken token) => db.RefreshTokens.Add(token);
}

internal sealed class UserProfileRepository(ReclaimDbContext db) : IUserProfileRepository
{
    public Task<UserProfile?> GetByAppUserIdAsync(Guid appUserId, CancellationToken cancellationToken = default) =>
        db.UserProfiles.FirstOrDefaultAsync(x => x.AppUserId == appUserId, cancellationToken);

    public Task<Guid?> GetIdByAppUserIdAsync(Guid appUserId, CancellationToken cancellationToken = default) =>
        db.UserProfiles.Where(x => x.AppUserId == appUserId).Select(x => (Guid?)x.Id).FirstOrDefaultAsync(cancellationToken);

    public void Add(UserProfile profile) => db.UserProfiles.Add(profile);
}

internal sealed class OnboardingResponseRepository(ReclaimDbContext db) : IOnboardingResponseRepository
{
    public Task<OnboardingResponse?> GetLatestAsync(Guid userProfileId, CancellationToken cancellationToken = default) =>
        db.OnboardingResponses.Where(x => x.UserProfileId == userProfileId).OrderByDescending(x => x.CreatedAtUtc).FirstOrDefaultAsync(cancellationToken);

    public Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.OnboardingResponses.AnyAsync(x => x.Id == id, cancellationToken);

    public void Add(OnboardingResponse response) => db.OnboardingResponses.Add(response);
}

internal sealed class SelfAssessmentRepository(ReclaimDbContext db) : ISelfAssessmentRepository
{
    public async Task<(IReadOnlyList<SelfAssessmentResult> Items, int TotalCount)> GetPageAsync(
        Guid userProfileId, int page, int pageSize, CancellationToken cancellationToken = default)
    {
        var query = db.SelfAssessmentResults.Where(x => x.UserProfileId == userProfileId);
        var total = await query.CountAsync(cancellationToken);
        var items = await query.OrderByDescending(x => x.CreatedAtUtc).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(cancellationToken);
        return (items, total);
    }

    public Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.SelfAssessmentResults.AnyAsync(x => x.Id == id, cancellationToken);

    public void Add(SelfAssessmentResult result) => db.SelfAssessmentResults.Add(result);
}

internal sealed class GamblingEntryRepository(ReclaimDbContext db) : IGamblingEntryRepository
{
    public Task<GamblingEntry?> GetAsync(Guid id, Guid userProfileId, CancellationToken cancellationToken = default) =>
        db.GamblingEntries.Include(x => x.Platform).FirstOrDefaultAsync(x => x.Id == id && x.UserProfileId == userProfileId, cancellationToken);

    public Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.GamblingEntries.AnyAsync(x => x.Id == id, cancellationToken);

    public async Task<(IReadOnlyList<GamblingEntry> Items, int TotalCount)> QueryAsync(
        Guid userProfileId, GamblingEntryFilter filter, CancellationToken cancellationToken = default)
    {
        var query = db.GamblingEntries.Where(x => x.UserProfileId == userProfileId);
        if (filter.FromUtc is { } from)
            query = query.Where(x => x.OccurredAtUtc >= from);
        if (filter.ToUtc is { } to)
            query = query.Where(x => x.OccurredAtUtc <= to);
        if (filter.EntryType is { } entryType)
            query = query.Where(x => x.EntryType == entryType);
        if (filter.GamblingType is { } gamblingType)
            query = query.Where(x => x.GamblingType == gamblingType);
        if (filter.PlatformId is { } platformId)
            query = query.Where(x => x.GamblingPlatformId == platformId);

        var total = await query.CountAsync(cancellationToken);
        var items = await query
            .Include(x => x.Platform)
            .OrderByDescending(x => x.OccurredAtUtc).ThenByDescending(x => x.CreatedAtUtc)
            .Skip((filter.Page - 1) * filter.PageSize).Take(filter.PageSize)
            .ToListAsync(cancellationToken);
        return (items, total);
    }

    public async Task<IReadOnlyDictionary<GamblingEntryType, decimal>> SumByTypeAsync(
        Guid userProfileId, DateTime? fromUtc, CancellationToken cancellationToken = default)
    {
        var query = db.GamblingEntries.Where(x => x.UserProfileId == userProfileId);
        if (fromUtc is { } from)
            query = query.Where(x => x.OccurredAtUtc >= from);
        return await query
            .GroupBy(x => x.EntryType)
            .Select(g => new { g.Key, Total = g.Sum(x => x.Amount) })
            .ToDictionaryAsync(x => x.Key, x => x.Total, cancellationToken);
    }

    public void Add(GamblingEntry entry) => db.GamblingEntries.Add(entry);

    public void Remove(GamblingEntry entry) => db.GamblingEntries.Remove(entry);
}

internal sealed class GamblingPlatformRepository(ReclaimDbContext db) : IGamblingPlatformRepository
{
    // Unsaved additions are checked first, so two lookups in one request share one new platform.
    public async Task<GamblingPlatform?> FindAsync(Guid userProfileId, string normalizedName, CancellationToken cancellationToken = default) =>
        db.GamblingPlatforms.Local.FirstOrDefault(x => x.CreatedByUserProfileId == userProfileId && x.NormalizedName == normalizedName)
        ?? await db.GamblingPlatforms.FirstOrDefaultAsync(
            x => (x.CreatedByUserProfileId == userProfileId || x.CreatedByUserProfileId == null) && x.NormalizedName == normalizedName,
            cancellationToken);

    public void Add(GamblingPlatform platform) => db.GamblingPlatforms.Add(platform);
}
