using FluentValidation;
using Microsoft.Extensions.DependencyInjection;
using Reclaim.Application.Assessment;
using Reclaim.Application.Auth;
using Reclaim.Application.GamblingEntries;
using Reclaim.Application.Onboarding;
using Reclaim.Application.Profile;

namespace Reclaim.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly, ServiceLifetime.Singleton);

        services.AddScoped<AuthTokenIssuer>();
        services.AddScoped<RegisterHandler>();
        services.AddScoped<LoginHandler>();
        services.AddScoped<RefreshHandler>();
        services.AddScoped<LogoutHandler>();
        services.AddScoped<DeleteAccountHandler>();
        services.AddScoped<PurgeDeletedAccountsHandler>();

        services.AddScoped<GetProfileHandler>();
        services.AddScoped<UpdateProfileHandler>();

        services.AddScoped<SubmitOnboardingHandler>();
        services.AddScoped<GetLatestOnboardingHandler>();

        services.AddSingleton<GetQuestionnaireHandler>();
        services.AddScoped<SubmitAssessmentHandler>();
        services.AddScoped<GetAssessmentHistoryHandler>();

        services.AddScoped<PlatformResolver>();
        services.AddScoped<CreateGamblingEntryHandler>();
        services.AddScoped<UpdateGamblingEntryHandler>();
        services.AddScoped<DeleteGamblingEntryHandler>();
        services.AddScoped<ListGamblingEntriesHandler>();
        services.AddScoped<GetGamblingStatsHandler>();
        return services;
    }
}
