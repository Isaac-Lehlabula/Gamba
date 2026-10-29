namespace Reclaim.Application.Common;

/// <summary>Credentials or tokens were rejected. The message is deliberately generic.</summary>
public sealed class AuthenticationFailedException() : Exception("Authentication failed.");

public sealed class ConflictException(string message) : Exception(message);

public sealed class NotFoundException(string message) : Exception(message);

public sealed class AccountDeletionOptions
{
    public const string SectionName = "AccountDeletion";

    /// <summary>How long a deleted account stays recoverable before it is hard-deleted.</summary>
    public int GracePeriodDays { get; set; } = 7;
}

public static class DateTimeExtensions
{
    /// <summary>The API contract is UTC throughout, so a timestamp without an offset is read as UTC, not server-local.</summary>
    public static DateTime AsUtc(this DateTime value) =>
        value.Kind == DateTimeKind.Unspecified ? DateTime.SpecifyKind(value, DateTimeKind.Utc) : value.ToUniversalTime();
}

public sealed record PagedResponse<T>(IReadOnlyList<T> Items, int Page, int PageSize, int TotalCount);

public static class Paging
{
    public const int DefaultPageSize = 50;
    public const int MaxPageSize = 200;
}

public static class ProfileLookup
{
    /// <summary>Every account has a profile from registration, so a missing one is a 404, not a crash.</summary>
    public static async Task<Guid> RequireIdAsync(this Abstractions.IUserProfileRepository profiles, Guid appUserId, CancellationToken cancellationToken)
        => await profiles.GetIdByAppUserIdAsync(appUserId, cancellationToken) ?? throw new NotFoundException("Profile not found.");
}
