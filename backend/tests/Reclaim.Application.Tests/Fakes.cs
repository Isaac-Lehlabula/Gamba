using Microsoft.Extensions.Options;
using Microsoft.Extensions.Time.Testing;
using Reclaim.Application.Auth;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Auditing;
using Reclaim.Domain.Users;

namespace Reclaim.Application.Tests;

internal sealed class InMemoryStore : IAppUserRepository, IRefreshTokenRepository, IUserProfileRepository, IUnitOfWork, IAuditLogger
{
    public List<AppUser> Users { get; } = [];
    public List<RefreshToken> Tokens { get; } = [];
    public List<UserProfile> Profiles { get; } = [];
    public List<AuditEventType> Audit { get; } = [];
    public int SaveCount { get; private set; }

    public Task<AppUser?> GetByIdAsync(Guid id, CancellationToken ct = default) => Task.FromResult(Users.FirstOrDefault(u => u.Id == id));
    public Task<AppUser?> GetByEmailAsync(string email, CancellationToken ct = default) => Task.FromResult(Users.FirstOrDefault(u => u.Email == email));
    public Task<bool> IsActiveAsync(Guid id, CancellationToken ct = default) => Task.FromResult(Users.Any(u => u.Id == id && !u.IsDeleted));
    public Task<IReadOnlyList<AppUser>> GetDeletedBeforeAsync(DateTime before, int max, CancellationToken ct = default) =>
        Task.FromResult<IReadOnlyList<AppUser>>(Users.Where(u => u.DeletedAtUtc < before).Take(max).ToList());
    public void Add(AppUser user) => Users.Add(user);
    public void Remove(AppUser user) => Users.Remove(user);

    public Task<RefreshToken?> GetByHashAsync(string hash, CancellationToken ct = default) => Task.FromResult(Tokens.FirstOrDefault(t => t.TokenHash == hash));
    public Task<IReadOnlyList<RefreshToken>> GetUnrevokedByFamilyAsync(Guid familyId, CancellationToken ct = default) =>
        Task.FromResult<IReadOnlyList<RefreshToken>>(Tokens.Where(t => t.FamilyId == familyId && !t.IsRevoked).ToList());
    public Task<IReadOnlyList<RefreshToken>> GetUnrevokedByUserAsync(Guid userId, CancellationToken ct = default) =>
        Task.FromResult<IReadOnlyList<RefreshToken>>(Tokens.Where(t => t.AppUserId == userId && !t.IsRevoked).ToList());
    public void Add(RefreshToken token) => Tokens.Add(token);

    public Task<UserProfile?> GetByAppUserIdAsync(Guid userId, CancellationToken ct = default) => Task.FromResult(Profiles.FirstOrDefault(p => p.AppUserId == userId));
    public Task<Guid?> GetIdByAppUserIdAsync(Guid userId, CancellationToken ct = default) =>
        Task.FromResult(Profiles.FirstOrDefault(p => p.AppUserId == userId)?.Id);
    public void Add(UserProfile profile) => Profiles.Add(profile);

    public Task SaveChangesAsync(CancellationToken ct = default)
    {
        SaveCount++;
        return Task.CompletedTask;
    }

    public void Record(AuditEventType eventType, Guid? appUserId, object? metadata = null) => Audit.Add(eventType);
}

internal sealed class FakePasswordHasher : IPasswordHasher
{
    public string Algorithm => "fake";
    public string Hash(string password) => "hashed:" + password;
    public PasswordVerificationResult Verify(string password, string hash, string algorithm) =>
        hash == Hash(password) ? PasswordVerificationResult.Success : PasswordVerificationResult.Failed;
}

internal sealed class FakeTokenService(TimeProvider time) : ITokenService
{
    public TimeSpan RefreshTokenLifetime => TimeSpan.FromDays(30);
    public AccessToken CreateAccessToken(AppUser user) => new($"access:{user.Id}", time.GetUtcNow().UtcDateTime.AddMinutes(15));
    public string GenerateRefreshToken() => Guid.NewGuid().ToString("N");
    public string HashRefreshToken(string refreshToken) => "h:" + refreshToken;
}

/// <summary>Wires the real handlers over in-memory fakes.</summary>
internal sealed class AuthHarness
{
    public FakeTimeProvider Time { get; } = new(new DateTimeOffset(2026, 10, 1, 12, 0, 0, TimeSpan.Zero));
    public InMemoryStore Store { get; } = new();
    public FakePasswordHasher Hasher { get; } = new();
    public FakeTokenService Tokens { get; }
    public AuthTokenIssuer Issuer { get; }

    public AuthHarness()
    {
        Tokens = new FakeTokenService(Time);
        Issuer = new AuthTokenIssuer(Tokens, Store, Time);
    }

    public RegisterHandler Register => new(Store, Store, Hasher, Issuer, Store, Store, Time);
    public LoginHandler Login => new(Store, Hasher, Issuer, Store, Store, Time);
    public RefreshHandler Refresh => new(Store, Store, Tokens, Issuer, Store, Store, Time);
    public LogoutHandler Logout => new(Store, Tokens, Store, Store, Time);
    public DeleteAccountHandler DeleteAccount => new(Store, Store, Store, Store, Time);
    public PurgeDeletedAccountsHandler Purge => new(Store, Store, Store, Options.Create(new AccountDeletionOptions { GracePeriodDays = 7 }), Time);
}
