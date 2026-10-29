using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Infrastructure.Auditing;
using Reclaim.Infrastructure.Jobs;
using Reclaim.Infrastructure.Persistence;
using Reclaim.Infrastructure.Security;

namespace Reclaim.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("Reclaim")
            ?? throw new InvalidOperationException("Connection string 'ConnectionStrings:Reclaim' is not configured.");
        services.AddDbContext<ReclaimDbContext>(o => o.UseNpgsql(connectionString));
        services.AddScoped<IUnitOfWork>(sp => sp.GetRequiredService<ReclaimDbContext>());

        services.AddOptions<JwtOptions>()
            .Bind(configuration.GetSection(JwtOptions.SectionName))
            .Validate(o => System.Text.Encoding.UTF8.GetByteCount(o.SigningKey) >= JwtOptions.MinSigningKeyBytes,
                $"Jwt:SigningKey must be at least {JwtOptions.MinSigningKeyBytes} bytes.")
            .ValidateOnStart();
        services.AddOptions<AuditOptions>()
            .Bind(configuration.GetSection(AuditOptions.SectionName))
            .Validate(o => o.IpHashKey.Length >= 32, "Audit:IpHashKey must be at least 32 characters.")
            .ValidateOnStart();
        services.AddOptions<FieldEncryptionOptions>()
            .Bind(configuration.GetSection(FieldEncryptionOptions.SectionName))
            .Validate(o => o.Keys.ContainsKey(o.ActiveKeyId), "FieldEncryption:ActiveKeyId must name one of FieldEncryption:Keys.")
            .ValidateOnStart();
        services.AddSingleton<FieldEncryptor>();
        services.AddOptions<PasswordHashingOptions>().Bind(configuration.GetSection(PasswordHashingOptions.SectionName));
        services.AddOptions<AccountDeletionOptions>().Bind(configuration.GetSection(AccountDeletionOptions.SectionName));

        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<IPasswordHasher, Pbkdf2PasswordHasher>();
        services.AddSingleton<ITokenService, JwtTokenService>();
        services.AddScoped<IAuditLogger, AuditLogger>();

        services.AddScoped<IAppUserRepository, AppUserRepository>();
        services.AddScoped<IRefreshTokenRepository, RefreshTokenRepository>();
        services.AddScoped<IUserProfileRepository, UserProfileRepository>();
        services.AddScoped<IOnboardingResponseRepository, OnboardingResponseRepository>();
        services.AddScoped<ISelfAssessmentRepository, SelfAssessmentRepository>();
        services.AddScoped<IGamblingEntryRepository, GamblingEntryRepository>();
        services.AddScoped<IGamblingPlatformRepository, GamblingPlatformRepository>();

        services.AddHostedService<AccountPurgeService>();
        services.AddHealthChecks().AddDbContextCheck<ReclaimDbContext>("database");
        return services;
    }
}
