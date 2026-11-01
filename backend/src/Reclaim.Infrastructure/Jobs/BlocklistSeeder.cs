using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Reclaim.Domain.Content;
using Reclaim.Domain.Gambling;
using Reclaim.Infrastructure.Persistence;

namespace Reclaim.Infrastructure.Jobs;

/// <summary>
/// Adds any starter-list domains missing from the blocklist. Never reactivates or edits existing
/// rows, so changes made by curators aren't undone on the next deploy.
/// </summary>
internal sealed class BlocklistSeeder(IServiceScopeFactory scopes, TimeProvider time, ILogger<BlocklistSeeder> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var scope = scopes.CreateAsyncScope();
            var added = await SeedAsync(scope.ServiceProvider.GetRequiredService<ReclaimDbContext>(), time.GetUtcNow().UtcDateTime, cancellationToken);
            if (added > 0)
                logger.LogInformation("Seeded {Count} blocklist domains", added);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // The API is still useful without the seed (e.g. database not migrated yet); don't block startup.
            logger.LogWarning(ex, "Blocklist seeding skipped");
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    /// <returns>How many domains were added.</returns>
    internal static async Task<int> SeedAsync(ReclaimDbContext db, DateTime nowUtc, CancellationToken cancellationToken = default)
    {
        var existing = (await db.BlocklistDomains.Select(d => d.Domain).ToListAsync(cancellationToken)).ToHashSet();
        var added = 0;
        foreach (var (domain, category) in ReadSeed())
        {
            if (!existing.Add(domain)) continue;
            db.BlocklistDomains.Add(BlocklistDomain.Create(domain, category, BlocklistSource.Curated, nowUtc));
            added++;
        }
        if (added > 0) await db.SaveChangesAsync(cancellationToken);
        return added;
    }

    internal static IEnumerable<(string Domain, GamblingType Category)> ReadSeed()
    {
        using var stream = typeof(BlocklistSeeder).Assembly.GetManifestResourceStream("Reclaim.Infrastructure.Seed.blocklist-seed.txt")
            ?? throw new InvalidOperationException("Blocklist seed resource is missing.");
        using var reader = new StreamReader(stream);
        while (reader.ReadLine() is { } line)
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0 || trimmed.StartsWith('#')) continue;
            var parts = trimmed.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            yield return (BlocklistDomain.Normalize(parts[0]), Enum.Parse<GamblingType>(parts[1]));
        }
    }
}
