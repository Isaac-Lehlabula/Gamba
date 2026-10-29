using System.Security.Claims;
using System.Security.Cryptography;
using FluentValidation;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.IdentityModel.JsonWebTokens;
using Reclaim.Application.Common.Abstractions;

namespace Reclaim.Api.Infrastructure;

internal sealed class HttpRequestContext(IHttpContextAccessor accessor) : IRequestContext
{
    // Null outside a request (e.g. background jobs).
    public string? IpAddress => accessor.HttpContext?.Connection.RemoteIpAddress?.ToString();
}

/// <summary>Runs the FluentValidation validator for every action argument before the action executes.</summary>
internal sealed class ValidationFilter(IServiceProvider services) : IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        foreach (var argument in context.ActionArguments.Values)
        {
            if (argument is null)
                continue;
            var validatorType = typeof(IValidator<>).MakeGenericType(argument.GetType());
            if (services.GetService(validatorType) is not IValidator validator)
                continue;

            var result = await validator.ValidateAsync(new ValidationContext<object>(argument), context.HttpContext.RequestAborted);
            if (!result.IsValid)
                throw new ValidationException(result.Errors);
        }
        await next();
    }
}

public static class ClaimsPrincipalExtensions
{
    public static Guid? FindUserId(this ClaimsPrincipal principal) =>
        Guid.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id) ? id : null;

    /// <summary>For use behind [Authorize], where a valid subject is guaranteed.</summary>
    public static Guid GetUserId(this ClaimsPrincipal principal) =>
        principal.FindUserId() ?? throw new InvalidOperationException("Authenticated principal has no subject.");
}

internal static class DevelopmentSecrets
{
    /// <summary>
    /// Fills in random signing/hashing keys when none are configured, so a fresh clone runs
    /// without committed secrets. Tokens stop validating when the process restarts.
    /// </summary>
    public static void EnsureConfigured(ConfigurationManager configuration)
    {
        var missing = new Dictionary<string, string?>();
        foreach (var key in new[] { "Jwt:SigningKey", "Audit:IpHashKey" })
        {
            if (string.IsNullOrEmpty(configuration[key]))
                missing[key] = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        }
        if (missing.Count > 0)
            configuration.AddInMemoryCollection(missing);
    }
}
