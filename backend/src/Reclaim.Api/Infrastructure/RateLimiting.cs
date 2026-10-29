using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;

namespace Reclaim.Api.Infrastructure;

public sealed class RateLimitingOptions
{
    public const string SectionName = "RateLimiting";

    public int AuthPermitsPerMinutePerIp { get; set; } = 10;
    public int RequestsPerMinutePerUser { get; set; } = 120;
}

public static class RateLimiting
{
    /// <summary>Strict per-IP limit for credential endpoints, to blunt brute force and stuffing.</summary>
    public const string AuthPolicy = "auth";

    /// <summary>Per-user limit for the authenticated API (falls back to per-IP when anonymous).</summary>
    public const string PerUserPolicy = "per-user";

    public static IServiceCollection AddReclaimRateLimiting(this IServiceCollection services, IConfiguration configuration)
    {
        var options = configuration.GetSection(RateLimitingOptions.SectionName).Get<RateLimitingOptions>() ?? new();

        services.AddRateLimiter(limiter =>
        {
            limiter.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

            limiter.AddPolicy(AuthPolicy, context => RateLimitPartition.GetFixedWindowLimiter(
                ClientIp(context),
                _ => new FixedWindowRateLimiterOptions { PermitLimit = options.AuthPermitsPerMinutePerIp, Window = TimeSpan.FromMinutes(1) }));

            limiter.AddPolicy(PerUserPolicy, context => RateLimitPartition.GetFixedWindowLimiter(
                context.User.FindUserId()?.ToString() ?? ClientIp(context),
                _ => new FixedWindowRateLimiterOptions { PermitLimit = options.RequestsPerMinutePerUser, Window = TimeSpan.FromMinutes(1) }));
        });
        return services;
    }

    private static string ClientIp(HttpContext context) => context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
}
