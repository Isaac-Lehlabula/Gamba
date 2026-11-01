using Microsoft.EntityFrameworkCore;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Content;
using Reclaim.Domain.Goals;
using Reclaim.Domain.Urges;

namespace Reclaim.Infrastructure.Persistence;

internal sealed class UrgeRepository(ReclaimDbContext db) : IUrgeRepository
{
    public Task<Urge?> GetAsync(Guid id, Guid userProfileId, CancellationToken cancellationToken = default) =>
        db.Urges.FirstOrDefaultAsync(x => x.Id == id && x.UserProfileId == userProfileId, cancellationToken);

    public Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.Urges.AnyAsync(x => x.Id == id, cancellationToken);

    public async Task<(IReadOnlyList<Urge> Items, int TotalCount)> GetPageAsync(Guid userProfileId, int page, int pageSize, CancellationToken cancellationToken = default)
    {
        var query = db.Urges.Where(x => x.UserProfileId == userProfileId);
        var total = await query.CountAsync(cancellationToken);
        var items = await query.OrderByDescending(x => x.StartedAtUtc).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(cancellationToken);
        return (items, total);
    }

    public async Task<IReadOnlyList<DateTime>> GetGambledDatesAsync(Guid userProfileId, CancellationToken cancellationToken = default) =>
        await db.Urges
            .Where(x => x.UserProfileId == userProfileId && x.Outcome == UrgeOutcome.Gambled)
            .Select(x => x.ResolvedAtUtc ?? x.StartedAtUtc)
            .ToListAsync(cancellationToken);

    public void Add(Urge urge) => db.Urges.Add(urge);
}

internal sealed class GoalRepository(ReclaimDbContext db) : IGoalRepository
{
    public Task<RecoveryGoal?> GetAsync(Guid id, Guid userProfileId, CancellationToken cancellationToken = default) =>
        db.RecoveryGoals.Include(x => x.Contributions).FirstOrDefaultAsync(x => x.Id == id && x.UserProfileId == userProfileId, cancellationToken);

    public async Task<IReadOnlyList<RecoveryGoal>> ListAsync(Guid userProfileId, CancellationToken cancellationToken = default) =>
        await db.RecoveryGoals.Include(x => x.Contributions)
            .Where(x => x.UserProfileId == userProfileId).OrderBy(x => x.CreatedAtUtc).ToListAsync(cancellationToken);

    public Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.RecoveryGoals.AnyAsync(x => x.Id == id, cancellationToken);

    public Task<bool> ContributionExistsAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.GoalContributions.AnyAsync(x => x.Id == id, cancellationToken);

    public void Add(RecoveryGoal goal) => db.RecoveryGoals.Add(goal);

    public void Remove(RecoveryGoal goal) => db.RecoveryGoals.Remove(goal);
}

internal sealed class GamblingActivityReader(ReclaimDbContext db) : IGamblingActivityReader
{
    public async Task<IReadOnlyList<EntryActivity>> GetActivityAsync(Guid userProfileId, CancellationToken cancellationToken = default) =>
        await db.GamblingEntries
            .Where(x => x.UserProfileId == userProfileId)
            .Select(x => new EntryActivity(x.EntryType, x.Amount, x.OccurredAtUtc))
            .ToListAsync(cancellationToken);
}

internal sealed class BlocklistRepository(ReclaimDbContext db) : IBlocklistRepository
{
    public async Task<IReadOnlyList<BlocklistDomain>> GetChangedSinceAsync(DateTime? sinceUtc, CancellationToken cancellationToken = default)
    {
        var query = db.BlocklistDomains.AsNoTracking();
        if (sinceUtc is { } since) query = query.Where(x => x.UpdatedAtUtc > since);
        return await query.OrderBy(x => x.UpdatedAtUtc).ThenBy(x => x.Domain).ToListAsync(cancellationToken);
    }

    public Task<BlocklistDomain?> FindAsync(string normalizedDomain, CancellationToken cancellationToken = default) =>
        db.BlocklistDomains.FirstOrDefaultAsync(x => x.Domain == normalizedDomain, cancellationToken);

    public void Add(BlocklistDomain domain) => db.BlocklistDomains.Add(domain);
}

internal sealed class SupportResourceRepository(ReclaimDbContext db) : ISupportResourceRepository
{
    public async Task<IReadOnlyList<SupportResource>> GetVerifiedAsync(CancellationToken cancellationToken = default) =>
        await db.SupportResources.AsNoTracking().Where(x => x.IsVerified)
            .OrderBy(x => x.Category).ThenBy(x => x.Name).ToListAsync(cancellationToken);
}
