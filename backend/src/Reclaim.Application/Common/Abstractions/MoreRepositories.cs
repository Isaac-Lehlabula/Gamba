using Reclaim.Domain.Content;
using Reclaim.Domain.Gambling;
using Reclaim.Domain.Goals;
using Reclaim.Domain.Urges;

namespace Reclaim.Application.Common.Abstractions;

public interface IUrgeRepository
{
    /// <summary>Only returns the urge if it belongs to the profile.</summary>
    Task<Urge?> GetAsync(Guid id, Guid userProfileId, CancellationToken cancellationToken = default);

    Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>Newest first.</summary>
    Task<(IReadOnlyList<Urge> Items, int TotalCount)> GetPageAsync(Guid userProfileId, int page, int pageSize, CancellationToken cancellationToken = default);

    /// <summary>When urges that ended in gambling were resolved, for streaks.</summary>
    Task<IReadOnlyList<DateTime>> GetGambledDatesAsync(Guid userProfileId, CancellationToken cancellationToken = default);

    void Add(Urge urge);
}

public interface IGoalRepository
{
    /// <summary>With contributions loaded; only if it belongs to the profile.</summary>
    Task<RecoveryGoal?> GetAsync(Guid id, Guid userProfileId, CancellationToken cancellationToken = default);

    /// <summary>Oldest first, with contributions loaded.</summary>
    Task<IReadOnlyList<RecoveryGoal>> ListAsync(Guid userProfileId, CancellationToken cancellationToken = default);

    Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default);

    Task<bool> ContributionExistsAsync(Guid id, CancellationToken cancellationToken = default);

    void Add(RecoveryGoal goal);

    void Remove(RecoveryGoal goal);
}

/// <summary>The minimum about an entry that dashboard maths needs.</summary>
public sealed record EntryActivity(GamblingEntryType Type, decimal Amount, DateTime OccurredAtUtc);

public interface IGamblingActivityReader
{
    Task<IReadOnlyList<EntryActivity>> GetActivityAsync(Guid userProfileId, CancellationToken cancellationToken = default);
}

public interface IBlocklistRepository
{
    /// <summary>Every row (active or not) changed after <paramref name="sinceUtc"/>, oldest change first.</summary>
    Task<IReadOnlyList<BlocklistDomain>> GetChangedSinceAsync(DateTime? sinceUtc, CancellationToken cancellationToken = default);

    Task<BlocklistDomain?> FindAsync(string normalizedDomain, CancellationToken cancellationToken = default);

    void Add(BlocklistDomain domain);
}

public interface ISupportResourceRepository
{
    Task<IReadOnlyList<SupportResource>> GetVerifiedAsync(CancellationToken cancellationToken = default);
}
