using Reclaim.Domain.Common;

namespace Reclaim.Domain.Users;

/// <summary>An optional account. Only exists if the user opts in to backup/sync.</summary>
public sealed class AppUser : Entity
{
    public const int MaxEmailLength = 320;

    private AppUser() { }

    public string Email { get; private set; } = null!;
    public string PasswordHash { get; private set; } = null!;
    public string PasswordHashAlgorithm { get; private set; } = null!;
    public DateTime? EmailVerifiedAtUtc { get; private set; }

    /// <summary>Set when deletion is requested; the account is hard-deleted after the grace period.</summary>
    public DateTime? DeletedAtUtc { get; private set; }

    public bool IsDeleted => DeletedAtUtc is not null;

    public static AppUser Create(string email, string passwordHash, string passwordHashAlgorithm, DateTime nowUtc)
    {
        var user = new AppUser
        {
            Email = NormalizeEmail(email),
            PasswordHash = passwordHash,
            PasswordHashAlgorithm = passwordHashAlgorithm,
        };
        user.Stamp(nowUtc);
        return user;
    }

    public static string NormalizeEmail(string email)
    {
        var normalized = email.Trim().ToLowerInvariant();
        if (normalized.Length == 0 || normalized.Length > MaxEmailLength || !normalized.Contains('@'))
            throw new DomainException("Email address is not valid.");
        return normalized;
    }

    public void ChangePasswordHash(string passwordHash, string passwordHashAlgorithm, DateTime nowUtc)
    {
        PasswordHash = passwordHash;
        PasswordHashAlgorithm = passwordHashAlgorithm;
        Touch(nowUtc);
    }

    public void RequestDeletion(DateTime nowUtc)
    {
        if (IsDeleted) return;
        DeletedAtUtc = nowUtc;
        Touch(nowUtc);
    }
}
