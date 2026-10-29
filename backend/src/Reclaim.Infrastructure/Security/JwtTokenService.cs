using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Users;

namespace Reclaim.Infrastructure.Security;

public sealed class JwtOptions
{
    public const string SectionName = "Jwt";
    public const int MinSigningKeyBytes = 32;

    public string Issuer { get; set; } = "reclaim-api";
    public string Audience { get; set; } = "reclaim-mobile";

    /// <summary>HMAC-SHA256 key, at least 32 bytes. Never committed; supplied via environment/secrets.</summary>
    public string SigningKey { get; set; } = "";

    public int AccessTokenMinutes { get; set; } = 15;
    public int RefreshTokenDays { get; set; } = 30;

    public SymmetricSecurityKey GetSecurityKey() => new(Encoding.UTF8.GetBytes(SigningKey));
}

internal sealed class JwtTokenService(IOptions<JwtOptions> options, TimeProvider time) : ITokenService
{
    private readonly JsonWebTokenHandler _handler = new();

    public TimeSpan RefreshTokenLifetime => TimeSpan.FromDays(options.Value.RefreshTokenDays);

    public AccessToken CreateAccessToken(AppUser user)
    {
        var o = options.Value;
        var now = time.GetUtcNow().UtcDateTime;
        var expires = now.AddMinutes(o.AccessTokenMinutes);

        // Deliberately minimal: no email or profile data in a token that may end up in logs or crash reports.
        var token = _handler.CreateToken(new SecurityTokenDescriptor
        {
            Issuer = o.Issuer,
            Audience = o.Audience,
            IssuedAt = now,
            NotBefore = now,
            Expires = expires,
            Subject = new ClaimsIdentity([
                new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            ]),
            SigningCredentials = new SigningCredentials(o.GetSecurityKey(), SecurityAlgorithms.HmacSha256),
        });
        return new AccessToken(token, expires);
    }

    public string GenerateRefreshToken() => Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(32));

    // The token carries 256 bits of randomness, so an unsalted SHA-256 is not brute-forceable
    // and stays deterministic, which the by-hash lookup needs.
    public string HashRefreshToken(string refreshToken) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(refreshToken)));
}
