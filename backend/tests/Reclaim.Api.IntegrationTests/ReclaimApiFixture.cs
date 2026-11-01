using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Reclaim.Application.Auth;
using Reclaim.Infrastructure.Persistence;
using Testcontainers.PostgreSql;

namespace Reclaim.Api.IntegrationTests;

/// <summary>
/// Runs the real API against a throwaway Postgres container. When Docker isn't available the
/// tests that need it are skipped rather than failed.
/// </summary>
public sealed class ReclaimApiFixture : IAsyncLifetime
{
    private PostgreSqlContainer? _postgres;
    private WebApplicationFactory<Program>? _factory;

    /// <summary>Matches the API's serializer settings (camelCase, enums as strings).</summary>
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { Converters = { new JsonStringEnumConverter() } };

    public string? UnavailableReason { get; private set; }

    public IServiceProvider Services => _factory!.Services;

    public async Task InitializeAsync()
    {
        try
        {
            _postgres = new PostgreSqlBuilder("postgres:16-alpine").Build();
            await _postgres.StartAsync();
        }
        catch (Exception ex)
        {
            UnavailableReason = $"Docker is not available for Testcontainers: {ex.GetType().Name}";
            return;
        }

        _factory = new WebApplicationFactory<Program>().WithWebHostBuilder(b =>
        {
            b.UseEnvironment("Testing");
            b.UseSetting("ConnectionStrings:Reclaim", _postgres.GetConnectionString());
            b.UseSetting("Jwt:SigningKey", "integration-test-signing-key-that-is-long-enough");
            b.UseSetting("Audit:IpHashKey", "integration-test-ip-hash-key-that-is-long-enough");
            b.UseSetting("FieldEncryption:ActiveKeyId", "test");
            b.UseSetting("FieldEncryption:Keys:test", Convert.ToBase64String(new byte[32]));
            b.UseSetting("PasswordHashing:Iterations", "1000");
            b.UseSetting("RateLimiting:AuthPermitsPerMinutePerIp", "10000");
            b.UseSetting("RateLimiting:RequestsPerMinutePerUser", "10000");
        });

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<ReclaimDbContext>();
        await db.Database.MigrateAsync();
        // The startup seeder ran before this migration, so seed now, as a deploy would after migrating.
        await Reclaim.Infrastructure.Jobs.BlocklistSeeder.SeedAsync(db, DateTime.UtcNow);
    }

    public HttpClient CreateClient() => _factory!.CreateClient();

    public async Task<(HttpClient Client, AuthResponse Session)> RegisterAsync(string? email = null)
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(email ?? $"{Guid.NewGuid():N}@example.com", "correct horse", null));
        response.EnsureSuccessStatusCode();
        var session = (await response.Content.ReadFromJsonAsync<AuthResponse>())!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session.AccessToken);
        return (client, session);
    }

    public async Task DisposeAsync()
    {
        if (_factory is not null)
            await _factory.DisposeAsync();
        if (_postgres is not null)
            await _postgres.DisposeAsync();
    }
}

[CollectionDefinition(Name)]
public sealed class ApiCollection : ICollectionFixture<ReclaimApiFixture>
{
    public const string Name = "api";
}
