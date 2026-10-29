using Reclaim.Domain.Users;

namespace Reclaim.Application.Common.Abstractions;

public interface IAppUserRepository
{
    Task<AppUser?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>Includes accounts pending deletion, so their email cannot be re-registered mid-grace-period.</summary>
    Task<AppUser?> GetByEmailAsync(string normalizedEmail, CancellationToken cancellationToken = default);

    Task<bool> IsActiveAsync(Guid id, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<AppUser>> GetDeletedBeforeAsync(DateTime deletedBeforeUtc, int maxCount, CancellationToken cancellationToken = default);

    void Add(AppUser user);

    /// <summary>Hard-deletes the user; all owned rows cascade.</summary>
    void Remove(AppUser user);
}

public interface IRefreshTokenRepository
{
    Task<RefreshToken?> GetByHashAsync(string tokenHash, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RefreshToken>> GetUnrevokedByFamilyAsync(Guid familyId, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RefreshToken>> GetUnrevokedByUserAsync(Guid appUserId, CancellationToken cancellationToken = default);

    void Add(RefreshToken token);
}

public interface IUserProfileRepository
{
    Task<UserProfile?> GetByAppUserIdAsync(Guid appUserId, CancellationToken cancellationToken = default);

    void Add(UserProfile profile);
}
