using Microsoft.EntityFrameworkCore;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Assessment;
using Reclaim.Domain.Auditing;
using Reclaim.Domain.Content;
using Reclaim.Domain.Gambling;
using Reclaim.Domain.Goals;
using Reclaim.Domain.Journal;
using Reclaim.Domain.Onboarding;
using Reclaim.Domain.Urges;
using Reclaim.Domain.Users;
using Reclaim.Infrastructure.Security;

namespace Reclaim.Infrastructure.Persistence;

public sealed class ReclaimDbContext(DbContextOptions<ReclaimDbContext> options, FieldEncryptor encryptor) : DbContext(options), IUnitOfWork
{
    public DbSet<AppUser> AppUsers => Set<AppUser>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<UserProfile> UserProfiles => Set<UserProfile>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<OnboardingResponse> OnboardingResponses => Set<OnboardingResponse>();
    public DbSet<SelfAssessmentResult> SelfAssessmentResults => Set<SelfAssessmentResult>();
    public DbSet<GamblingEntry> GamblingEntries => Set<GamblingEntry>();
    public DbSet<GamblingPlatform> GamblingPlatforms => Set<GamblingPlatform>();
    public DbSet<Urge> Urges => Set<Urge>();
    public DbSet<RecoveryGoal> RecoveryGoals => Set<RecoveryGoal>();
    public DbSet<GoalContribution> GoalContributions => Set<GoalContribution>();
    public DbSet<BlocklistDomain> BlocklistDomains => Set<BlocklistDomain>();
    public DbSet<SupportResource> SupportResources => Set<SupportResource>();
    public DbSet<JournalEntry> JournalEntries => Set<JournalEntry>();

    async Task IUnitOfWork.SaveChangesAsync(CancellationToken cancellationToken) =>
        await SaveChangesAsync(cancellationToken);

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Listed explicitly because some configurations need the encryptor. EF caches the model
        // per context type, so the encryptor captured here must be the registered singleton.
        modelBuilder
            .ApplyConfiguration(new AppUserConfiguration())
            .ApplyConfiguration(new RefreshTokenConfiguration())
            .ApplyConfiguration(new UserProfileConfiguration())
            .ApplyConfiguration(new AuditLogConfiguration())
            .ApplyConfiguration(new OnboardingResponseConfiguration(encryptor))
            .ApplyConfiguration(new SelfAssessmentResultConfiguration())
            .ApplyConfiguration(new GamblingEntryConfiguration(encryptor))
            .ApplyConfiguration(new GamblingPlatformConfiguration())
            .ApplyConfiguration(new UrgeConfiguration(encryptor))
            .ApplyConfiguration(new RecoveryGoalConfiguration())
            .ApplyConfiguration(new GoalContributionConfiguration())
            .ApplyConfiguration(new BlocklistDomainConfiguration())
            .ApplyConfiguration(new SupportResourceConfiguration())
            .ApplyConfiguration(new JournalEntryConfiguration(encryptor));
    }

    protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
    {
        // Enums are stored by name so the database stays readable and reordering members is safe.
        configurationBuilder.Properties<Enum>().HaveConversion<string>().HaveMaxLength(64);
    }
}
