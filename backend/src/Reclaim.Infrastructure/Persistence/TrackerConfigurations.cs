using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using Reclaim.Domain.Assessment;
using Reclaim.Domain.Gambling;
using Reclaim.Domain.Onboarding;
using Reclaim.Domain.Users;
using Reclaim.Infrastructure.Security;

namespace Reclaim.Infrastructure.Persistence;

internal sealed class EncryptedStringConverter(FieldEncryptor encryptor) : ValueConverter<string?, string?>(
    v => v == null ? null : encryptor.Encrypt(v),
    v => v == null ? null : encryptor.Decrypt(v));

internal sealed class OnboardingResponseConfiguration(FieldEncryptor encryptor) : IEntityTypeConfiguration<OnboardingResponse>
{
    public void Configure(EntityTypeBuilder<OnboardingResponse> b)
    {
        b.ToTable("OnboardingResponse");
        b.HasKey(x => x.Id);
        b.Property(x => x.Id).ValueGeneratedNever();
        b.PrimitiveCollection(x => x.GamblingTypes).ElementType(e => e.HasConversion<string>());
        b.PrimitiveCollection(x => x.Triggers).ElementType(e => e.HasConversion<string>());
        b.Property(x => x.ApproxMonthlySpend).HasPrecision(12, 2);
        b.Property(x => x.MoneyGoalPreference).HasConversion(new EncryptedStringConverter(encryptor));
        b.HasIndex(x => new { x.UserProfileId, x.CreatedAtUtc });
        b.HasOne<UserProfile>().WithMany().HasForeignKey(x => x.UserProfileId).OnDelete(DeleteBehavior.Cascade);
    }
}

internal sealed class GamblingEntryConfiguration(FieldEncryptor encryptor) : IEntityTypeConfiguration<GamblingEntry>
{
    public void Configure(EntityTypeBuilder<GamblingEntry> b)
    {
        b.ToTable("GamblingEntry");
        b.HasKey(x => x.Id);
        b.Property(x => x.Id).ValueGeneratedNever();
        b.Property(x => x.Amount).HasPrecision(12, 2);
        b.Property(x => x.Notes).HasConversion(new EncryptedStringConverter(encryptor));
        b.HasIndex(x => new { x.UserProfileId, x.OccurredAtUtc });
        b.HasOne<UserProfile>().WithMany().HasForeignKey(x => x.UserProfileId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne(x => x.Platform).WithMany().HasForeignKey(x => x.GamblingPlatformId).OnDelete(DeleteBehavior.SetNull);
    }
}

internal sealed class GamblingPlatformConfiguration : IEntityTypeConfiguration<GamblingPlatform>
{
    public void Configure(EntityTypeBuilder<GamblingPlatform> b)
    {
        b.ToTable("GamblingPlatform");
        b.HasKey(x => x.Id);
        b.Property(x => x.Name).HasMaxLength(GamblingPlatform.MaxNameLength).IsRequired();
        b.Property(x => x.NormalizedName).HasMaxLength(GamblingPlatform.MaxNameLength).IsRequired();
        b.HasIndex(x => new { x.CreatedByUserProfileId, x.NormalizedName }).IsUnique();
        b.HasOne<UserProfile>().WithMany().HasForeignKey(x => x.CreatedByUserProfileId).OnDelete(DeleteBehavior.Cascade);
    }
}

internal sealed class SelfAssessmentResultConfiguration : IEntityTypeConfiguration<SelfAssessmentResult>
{
    public void Configure(EntityTypeBuilder<SelfAssessmentResult> b)
    {
        b.ToTable("SelfAssessmentResult");
        b.HasKey(x => x.Id);
        b.Property(x => x.Id).ValueGeneratedNever();
        b.Property(x => x.Answers)
            .HasColumnType("jsonb")
            .HasConversion(
                v => JsonSerializer.Serialize(v, JsonSerializerOptions.Default),
                v => JsonSerializer.Deserialize<Dictionary<string, int>>(v, JsonSerializerOptions.Default) ?? new(),
                new ValueComparer<Dictionary<string, int>>(
                    (a, c) => a!.Count == c!.Count && !a.Except(c).Any(),
                    v => v.Aggregate(0, (h, kv) => HashCode.Combine(h, kv.Key, kv.Value)),
                    v => new Dictionary<string, int>(v)));
        b.HasIndex(x => new { x.UserProfileId, x.CreatedAtUtc });
        b.HasOne<UserProfile>().WithMany().HasForeignKey(x => x.UserProfileId).OnDelete(DeleteBehavior.Cascade);
    }
}
