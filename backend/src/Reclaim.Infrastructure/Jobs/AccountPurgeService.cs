using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Reclaim.Application.Auth;

namespace Reclaim.Infrastructure.Jobs;

/// <summary>Periodically hard-deletes accounts whose deletion grace period has passed.</summary>
internal sealed class AccountPurgeService(IServiceScopeFactory scopes, ILogger<AccountPurgeService> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromHours(1);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        do
        {
            try
            {
                await PurgeAllExpiredAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "Account purge run failed");
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    private async Task PurgeAllExpiredAsync(CancellationToken cancellationToken)
    {
        int purged;
        do
        {
            await using var scope = scopes.CreateAsyncScope();
            purged = await scope.ServiceProvider.GetRequiredService<PurgeDeletedAccountsHandler>().HandleAsync(cancellationToken);
            if (purged > 0)
                logger.LogInformation("Purged {Count} accounts past their deletion grace period", purged);
        }
        while (purged == PurgeDeletedAccountsHandler.BatchSize);
    }
}
