using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Reclaim.Domain.Auditing;
using Reclaim.Domain.Users;

namespace Reclaim.Infrastructure.Persistence;

internal sealed class AppUserConfiguration : IEntityTypeConfiguration<AppUser>
{
    public void Configure(EntityTypeBuilder<AppUser> b)
    {
        b.ToTable("AppUser");
        b.HasKey(x => x.Id);
        b.Property(x => x.Email).HasMaxLength(AppUser.MaxEmailLength).IsRequired();
        b.HasIndex(x => x.Email).IsUnique();
        b.Property(x => x.PasswordHash).HasMaxLength(512).IsRequired();
        b.Property(x => x.PasswordHashAlgorithm).HasMaxLength(64).IsRequired();
        b.HasIndex(x => x.DeletedAtUtc).HasFilter("\"DeletedAtUtc\" IS NOT NULL");
        b.Ignore(x => x.IsDeleted);
    }
}

internal sealed class RefreshTokenConfiguration : IEntityTypeConfiguration<RefreshToken>
{
    public void Configure(EntityTypeBuilder<RefreshToken> b)
    {
        b.ToTable("RefreshToken");
        b.HasKey(x => x.Id);
        b.Property(x => x.TokenHash).HasMaxLength(128).IsRequired();
        b.HasIndex(x => x.TokenHash).IsUnique();
        b.Property(x => x.ReplacedByTokenHash).HasMaxLength(128);
        b.HasIndex(x => x.FamilyId);
        b.HasIndex(x => x.AppUserId);
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.AppUserId).OnDelete(DeleteBehavior.Cascade);
        b.Ignore(x => x.IsRevoked);
    }
}

internal sealed class UserProfileConfiguration : IEntityTypeConfiguration<UserProfile>
{
    public void Configure(EntityTypeBuilder<UserProfile> b)
    {
        b.ToTable("UserProfile");
        b.HasKey(x => x.Id);
        b.HasIndex(x => x.AppUserId).IsUnique();
        b.HasIndex(x => x.LocalProfileId).IsUnique();
        b.Property(x => x.DisplayName).HasMaxLength(UserProfile.MaxDisplayNameLength);
        b.HasOne<AppUser>().WithOne().HasForeignKey<UserProfile>(x => x.AppUserId).OnDelete(DeleteBehavior.Cascade);
    }
}

internal sealed class AuditLogConfiguration : IEntityTypeConfiguration<AuditLog>
{
    public void Configure(EntityTypeBuilder<AuditLog> b)
    {
        b.ToTable("AuditLog");
        b.HasKey(x => x.Id);
        b.Property(x => x.Metadata).HasColumnType("jsonb");
        b.Property(x => x.IpAddressHash).HasMaxLength(128);
        b.HasIndex(x => x.CreatedAtUtc);
        b.HasIndex(x => x.AppUserId);
        // Audit history outlives a purged account, but no longer points at it.
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.AppUserId).OnDelete(DeleteBehavior.SetNull);
    }
}
