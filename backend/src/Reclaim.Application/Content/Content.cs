using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Content;
using Reclaim.Domain.Gambling;

namespace Reclaim.Application.Content;

public sealed record BlocklistItem(string Domain, GamblingType Category, bool IsActive, DateTime UpdatedAtUtc);

/// <param name="NextSince">Pass back as <c>since</c> on the next sync to get only later changes.</param>
public sealed record BlocklistResponse(IReadOnlyList<BlocklistItem> Items, DateTime? NextSince);

public sealed class GetBlocklistHandler(IBlocklistRepository blocklist)
{
    /// <summary>
    /// Everything changed after <paramref name="sinceUtc"/>, including deactivations, so clients
    /// can remove domains as well as add them. With no <c>since</c>, a full list of active domains.
    /// </summary>
    public async Task<BlocklistResponse> HandleAsync(DateTime? sinceUtc, CancellationToken ct = default)
    {
        var changed = await blocklist.GetChangedSinceAsync(sinceUtc, ct);
        var items = changed
            .Where(d => sinceUtc is not null || d.IsActive)
            .Select(d => new BlocklistItem(d.Domain, d.Category, d.IsActive, d.UpdatedAtUtc))
            .ToList();
        return new(items, changed.Count == 0 ? sinceUtc : changed.Max(d => d.UpdatedAtUtc));
    }
}

public sealed record SupportResourceResponse(
    Guid Id,
    string Name,
    SupportCategory Category,
    string Description,
    string? PhoneNumber,
    string? Website,
    string Region,
    DateTime? VerifiedAtUtc);

public sealed class GetSupportResourcesHandler(ISupportResourceRepository resources)
{
    /// <summary>Only verified resources are ever returned; unverified rows stay invisible to clients.</summary>
    public async Task<IReadOnlyList<SupportResourceResponse>> HandleAsync(CancellationToken ct = default) =>
        (await resources.GetVerifiedAsync(ct))
            .Select(r => new SupportResourceResponse(r.Id, r.Name, r.Category, r.Description, r.PhoneNumber, r.Website, r.Region, r.VerifiedAtUtc))
            .ToList();
}
