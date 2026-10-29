using Microsoft.EntityFrameworkCore;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Users;

namespace Reclaim.Infrastructure.Persistence;

internal sealed class AppUserRepository(ReclaimDbContext db) : IAppUserRepository
{
    public Task<AppUser?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.AppUsers.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);

    public Task<AppUser?> GetByEmailAsync(string normalizedEmail, CancellationToken cancellationToken = default) =>
        db.AppUsers.FirstOrDefaultAsync(x => x.Email == normalizedEmail, cancellationToken);

    public Task<bool> IsActiveAsync(Guid id, CancellationToken cancellationToken = default) =>
        db.AppUsers.AnyAsync(x => x.Id == id && x.DeletedAtUtc == null, cancellationToken);

    public async Task<IReadOnlyList<AppUser>> GetDeletedBeforeAsync(DateTime deletedBeforeUtc, int maxCount, CancellationToken cancellationToken = default) =>
        await db.AppUsers
            .Where(x => x.DeletedAtUtc != null && x.DeletedAtUtc < deletedBeforeUtc)
            .OrderBy(x => x.DeletedAtUtc)
            .Take(maxCount)
            .ToListAsync(cancellationToken);

    public void Add(AppUser user) => db.AppUsers.Add(user);

    public void Remove(AppUser user) => db.AppUsers.Remove(user);
}

internal sealed class RefreshTokenRepository(ReclaimDbContext db) : IRefreshTokenRepository
{
    public Task<RefreshToken?> GetByHashAsync(string tokenHash, CancellationToken cancellationToken = default) =>
        db.RefreshTokens.FirstOrDefaultAsync(x => x.TokenHash == tokenHash, cancellationToken);

    public async Task<IReadOnlyList<RefreshToken>> GetUnrevokedByFamilyAsync(Guid familyId, CancellationToken cancellationToken = default) =>
        await db.RefreshTokens.Where(x => x.FamilyId == familyId && x.RevokedAtUtc == null).ToListAsync(cancellationToken);

    public async Task<IReadOnlyList<RefreshToken>> GetUnrevokedByUserAsync(Guid appUserId, CancellationToken cancellationToken = default) =>
        await db.RefreshTokens.Where(x => x.AppUserId == appUserId && x.RevokedAtUtc == null).ToListAsync(cancellationToken);

    public void Add(RefreshToken token) => db.RefreshTokens.Add(token);
}

internal sealed class UserProfileRepository(ReclaimDbContext db) : IUserProfileRepository
{
    public Task<UserProfile?> GetByAppUserIdAsync(Guid appUserId, CancellationToken cancellationToken = default) =>
        db.UserProfiles.FirstOrDefaultAsync(x => x.AppUserId == appUserId, cancellationToken);

    public void Add(UserProfile profile) => db.UserProfiles.Add(profile);
}
