using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Reclaim.Domain.Content;
using Reclaim.Domain.Goals;
using Reclaim.Domain.Urges;
using Reclaim.Domain.Users;
using Reclaim.Infrastructure.Security;

namespace Reclaim.Infrastructure.Persistence;

internal sealed class UrgeConfiguration(FieldEncryptor encryptor) : IEntityTypeConfiguration<Urge>
{
    public void Configure(EntityTypeBuilder<Urge> b)
    {
        b.ToTable("Urge");
        b.HasKey(x => x.Id);
        b.Property(x => x.Id).ValueGeneratedNever();
        b.Property(x => x.Notes).HasConversion(new EncryptedStringConverter(encryptor));
        b.HasIndex(x => new { x.UserProfileId, x.StartedAtUtc });
        b.HasOne<UserProfile>().WithMany().HasForeignKey(x => x.UserProfileId).OnDelete(DeleteBehavior.Cascade);
        b.Ignore(x => x.IsResolved);
    }
}

internal sealed class RecoveryGoalConfiguration : IEntityTypeConfiguration<RecoveryGoal>
{
    public void Configure(EntityTypeBuilder<RecoveryGoal> b)
    {
        b.ToTable("RecoveryGoal");
        b.HasKey(x => x.Id);
        b.Property(x => x.Id).ValueGeneratedNever();
        b.Property(x => x.Name).HasMaxLength(RecoveryGoal.MaxNameLength).IsRequired();
        b.Property(x => x.TargetAmount).HasPrecision(12, 2);
        b.HasIndex(x => x.UserProfileId);
        b.HasOne<UserProfile>().WithMany().HasForeignKey(x => x.UserProfileId).OnDelete(DeleteBehavior.Cascade);
        b.HasMany(x => x.Contributions).WithOne().HasForeignKey(c => c.RecoveryGoalId).OnDelete(DeleteBehavior.Cascade);
        b.Navigation(x => x.Contributions).HasField("_contributions").UsePropertyAccessMode(PropertyAccessMode.Field);
        b.Ignore(x => x.SavedAmount);
    }
}

internal sealed class GoalContributionConfiguration : IEntityTypeConfiguration<GoalContribution>
{
    public void Configure(EntityTypeBuilder<GoalContribution> b)
    {
        b.ToTable("GoalContribution");
        b.HasKey(x => x.Id);
        b.Property(x => x.Id).ValueGeneratedNever();
        b.Property(x => x.Amount).HasPrecision(12, 2);
    }
}

internal sealed class BlocklistDomainConfiguration : IEntityTypeConfiguration<BlocklistDomain>
{
    public void Configure(EntityTypeBuilder<BlocklistDomain> b)
    {
        b.ToTable("BlocklistDomain");
        b.HasKey(x => x.Id);
        b.Property(x => x.Domain).HasMaxLength(BlocklistDomain.MaxDomainLength).IsRequired();
        b.HasIndex(x => x.Domain).IsUnique();
        b.HasIndex(x => x.UpdatedAtUtc);
    }
}

internal sealed class SupportResourceConfiguration : IEntityTypeConfiguration<SupportResource>
{
    public void Configure(EntityTypeBuilder<SupportResource> b)
    {
        b.ToTable("SupportResource");
        b.HasKey(x => x.Id);
        b.Property(x => x.Name).HasMaxLength(120).IsRequired();
        b.Property(x => x.Description).HasMaxLength(1000).IsRequired();
        b.Property(x => x.PhoneNumber).HasMaxLength(40);
        b.Property(x => x.Website).HasMaxLength(300);
        b.Property(x => x.Region).HasMaxLength(80).IsRequired();
        b.HasIndex(x => x.IsVerified);
    }
}
