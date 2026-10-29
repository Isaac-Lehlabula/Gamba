using FluentValidation;
using Microsoft.Extensions.DependencyInjection;
using Reclaim.Application.Auth;
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
        return services;
    }
}
