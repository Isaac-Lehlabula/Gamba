using Microsoft.EntityFrameworkCore;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Auditing;
using Reclaim.Domain.Users;

namespace Reclaim.Infrastructure.Persistence;

public sealed class ReclaimDbContext(DbContextOptions<ReclaimDbContext> options) : DbContext(options), IUnitOfWork
{
    public DbSet<AppUser> AppUsers => Set<AppUser>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<UserProfile> UserProfiles => Set<UserProfile>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();

    async Task IUnitOfWork.SaveChangesAsync(CancellationToken cancellationToken) =>
        await SaveChangesAsync(cancellationToken);

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(ReclaimDbContext).Assembly);
    }

    protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
    {
        // Enums are stored by name so the database stays readable and reordering members is safe.
        configurationBuilder.Properties<Enum>().HaveConversion<string>().HaveMaxLength(64);
    }
}
