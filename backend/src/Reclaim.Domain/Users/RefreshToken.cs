using Reclaim.Domain.Common;

namespace Reclaim.Domain.Users;

/// <summary>
/// A single-use refresh token, stored only as a hash. Every token issued from one login belongs
/// to the same <see cref="FamilyId"/>, so presenting an already-rotated token can revoke the
/// whole chain (theft detection).
/// </summary>
public sealed class RefreshToken : Entity
{
    private RefreshToken() { }

    public Guid AppUserId { get; private set; }
    public Guid FamilyId { get; private set; }
    public string TokenHash { get; private set; } = null!;
    public DateTime ExpiresAtUtc { get; private set; }
    public DateTime? RevokedAtUtc { get; private set; }
    public string? ReplacedByTokenHash { get; private set; }

    public bool IsRevoked => RevokedAtUtc is not null;

    public bool IsActive(DateTime nowUtc) => !IsRevoked && nowUtc < ExpiresAtUtc;

    public static RefreshToken Issue(Guid appUserId, Guid familyId, string tokenHash, DateTime expiresAtUtc, DateTime nowUtc)
    {
        if (expiresAtUtc <= nowUtc)
            throw new DomainException("Refresh token must expire in the future.");

        var token = new RefreshToken
        {
            AppUserId = appUserId,
            FamilyId = familyId,
            TokenHash = tokenHash,
            ExpiresAtUtc = expiresAtUtc,
        };
        token.Stamp(nowUtc);
        return token;
    }

    public void Revoke(DateTime nowUtc, string? replacedByTokenHash = null)
    {
        if (IsRevoked) return;
        RevokedAtUtc = nowUtc;
        ReplacedByTokenHash = replacedByTokenHash;
        Touch(nowUtc);
    }
}
