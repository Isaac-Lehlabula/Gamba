using Microsoft.Extensions.Options;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Auditing;
using Reclaim.Domain.Common;
using Reclaim.Domain.Users;

namespace Reclaim.Application.Auth;

/// <summary>Issues an access token plus a new refresh token in the given family.</summary>
public sealed class AuthTokenIssuer(ITokenService tokens, IRefreshTokenRepository refreshTokens, TimeProvider time)
{
    public AuthResponse Issue(AppUser user, Guid familyId, out string refreshTokenHash)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var access = tokens.CreateAccessToken(user);
        var rawRefresh = tokens.GenerateRefreshToken();
        refreshTokenHash = tokens.HashRefreshToken(rawRefresh);

        var refresh = RefreshToken.Issue(user.Id, familyId, refreshTokenHash, now + tokens.RefreshTokenLifetime, now);
        refreshTokens.Add(refresh);

        return new AuthResponse(user.Id, access.Token, access.ExpiresAtUtc, rawRefresh, refresh.ExpiresAtUtc);
    }

    public AuthResponse IssueNewFamily(AppUser user) => Issue(user, Guid.NewGuid(), out _);
}

public sealed class RegisterHandler(
    IAppUserRepository users,
    IUserProfileRepository profiles,
    IPasswordHasher hasher,
    AuthTokenIssuer issuer,
    IAuditLogger audit,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    public async Task<AuthResponse> HandleAsync(RegisterRequest request, CancellationToken cancellationToken = default)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var email = AppUser.NormalizeEmail(request.Email);

        if (await users.GetByEmailAsync(email, cancellationToken) is not null)
            throw new ConflictException("An account could not be created with this email address.");

        var user = AppUser.Create(email, hasher.Hash(request.Password), hasher.Algorithm, now);
        users.Add(user);
        profiles.Add(UserProfile.CreateForAccount(user.Id, request.LocalProfileId, now));
        audit.Record(AuditEventType.AccountRegistered, user.Id);

        var response = issuer.IssueNewFamily(user);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return response;
    }
}

public sealed class LoginHandler(
    IAppUserRepository users,
    IPasswordHasher hasher,
    AuthTokenIssuer issuer,
    IAuditLogger audit,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    public async Task<AuthResponse> HandleAsync(LoginRequest request, CancellationToken cancellationToken = default)
    {
        string email;
        try
        {
            email = AppUser.NormalizeEmail(request.Email);
        }
        catch (DomainException)
        {
            throw new AuthenticationFailedException();
        }

        var user = await users.GetByEmailAsync(email, cancellationToken);
        if (user is null || user.IsDeleted)
        {
            // Hash anyway so response timing doesn't reveal whether the account exists.
            hasher.Hash(request.Password);
            throw new AuthenticationFailedException();
        }

        var result = hasher.Verify(request.Password, user.PasswordHash, user.PasswordHashAlgorithm);
        if (result == PasswordVerificationResult.Failed)
        {
            audit.Record(AuditEventType.LoginFailed, user.Id);
            await unitOfWork.SaveChangesAsync(cancellationToken);
            throw new AuthenticationFailedException();
        }

        if (result == PasswordVerificationResult.SuccessRehashNeeded)
            user.ChangePasswordHash(hasher.Hash(request.Password), hasher.Algorithm, time.GetUtcNow().UtcDateTime);

        audit.Record(AuditEventType.LoginSucceeded, user.Id);
        var response = issuer.IssueNewFamily(user);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return response;
    }
}

public sealed class RefreshHandler(
    IAppUserRepository users,
    IRefreshTokenRepository refreshTokens,
    ITokenService tokens,
    AuthTokenIssuer issuer,
    IAuditLogger audit,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    public async Task<AuthResponse> HandleAsync(RefreshRequest request, CancellationToken cancellationToken = default)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var existing = await refreshTokens.GetByHashAsync(tokens.HashRefreshToken(request.RefreshToken), cancellationToken)
            ?? throw new AuthenticationFailedException();

        if (existing.IsRevoked)
        {
            // A rotated token was presented again: assume it was stolen and end the whole chain.
            foreach (var token in await refreshTokens.GetUnrevokedByFamilyAsync(existing.FamilyId, cancellationToken))
                token.Revoke(now);
            audit.Record(AuditEventType.RefreshTokenReuseDetected, existing.AppUserId, new { existing.FamilyId });
            await unitOfWork.SaveChangesAsync(cancellationToken);
            throw new AuthenticationFailedException();
        }

        if (!existing.IsActive(now))
            throw new AuthenticationFailedException();

        var user = await users.GetByIdAsync(existing.AppUserId, cancellationToken);
        if (user is null || user.IsDeleted)
            throw new AuthenticationFailedException();

        var response = issuer.Issue(user, existing.FamilyId, out var newHash);
        existing.Revoke(now, newHash);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return response;
    }
}

public sealed class LogoutHandler(
    IRefreshTokenRepository refreshTokens,
    ITokenService tokens,
    IAuditLogger audit,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    /// <summary>Ends the presented token's session (its whole family). Idempotent.</summary>
    public async Task HandleAsync(Guid appUserId, LogoutRequest request, CancellationToken cancellationToken = default)
    {
        var existing = await refreshTokens.GetByHashAsync(tokens.HashRefreshToken(request.RefreshToken), cancellationToken);
        if (existing is null || existing.AppUserId != appUserId)
            return;

        var now = time.GetUtcNow().UtcDateTime;
        foreach (var token in await refreshTokens.GetUnrevokedByFamilyAsync(existing.FamilyId, cancellationToken))
            token.Revoke(now);
        audit.Record(AuditEventType.Logout, appUserId);
        await unitOfWork.SaveChangesAsync(cancellationToken);
    }
}

public sealed class DeleteAccountHandler(
    IAppUserRepository users,
    IRefreshTokenRepository refreshTokens,
    IAuditLogger audit,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    /// <summary>Starts the deletion grace period and signs the account out everywhere.</summary>
    public async Task HandleAsync(Guid appUserId, CancellationToken cancellationToken = default)
    {
        var user = await users.GetByIdAsync(appUserId, cancellationToken)
            ?? throw new NotFoundException("Account not found.");
        if (user.IsDeleted)
            return;

        var now = time.GetUtcNow().UtcDateTime;
        user.RequestDeletion(now);
        foreach (var token in await refreshTokens.GetUnrevokedByUserAsync(appUserId, cancellationToken))
            token.Revoke(now);
        audit.Record(AuditEventType.AccountDeletionRequested, appUserId);
        await unitOfWork.SaveChangesAsync(cancellationToken);
    }
}

/// <summary>Hard-deletes accounts whose deletion grace period has passed.</summary>
public sealed class PurgeDeletedAccountsHandler(
    IAppUserRepository users,
    IAuditLogger audit,
    IUnitOfWork unitOfWork,
    IOptions<AccountDeletionOptions> options,
    TimeProvider time)
{
    public const int BatchSize = 100;

    /// <returns>The number of accounts purged in this batch.</returns>
    public async Task<int> HandleAsync(CancellationToken cancellationToken = default)
    {
        var cutoff = time.GetUtcNow().UtcDateTime.AddDays(-options.Value.GracePeriodDays);
        var expired = await users.GetDeletedBeforeAsync(cutoff, BatchSize, cancellationToken);
        if (expired.Count == 0)
            return 0;

        foreach (var user in expired)
            users.Remove(user);
        // No user id: the row it would reference is gone.
        audit.Record(AuditEventType.AccountPurged, null, new { expired.Count });
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return expired.Count;
    }
}
