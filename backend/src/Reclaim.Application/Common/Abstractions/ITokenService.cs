using Reclaim.Domain.Users;

namespace Reclaim.Application.Common.Abstractions;

public interface ITokenService
{
    TimeSpan RefreshTokenLifetime { get; }

    AccessToken CreateAccessToken(AppUser user);

    /// <summary>Creates a new high-entropy refresh token. Only its hash is ever persisted.</summary>
    string GenerateRefreshToken();

    string HashRefreshToken(string refreshToken);
}

public sealed record AccessToken(string Token, DateTime ExpiresAtUtc);
