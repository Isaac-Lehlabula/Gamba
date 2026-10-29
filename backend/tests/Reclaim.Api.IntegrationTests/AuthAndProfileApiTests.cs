using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Reclaim.Application.Auth;

namespace Reclaim.Api.IntegrationTests;

[Collection(ApiCollection.Name)]
public class AuthAndProfileApiTests(ReclaimApiFixture fixture)
{
    private void RequireDocker() => Skip.If(fixture.UnavailableReason is not null, fixture.UnavailableReason);

    [SkippableFact]
    public async Task Health_endpoint_reports_healthy()
    {
        RequireDocker();
        var response = await fixture.CreateClient().GetAsync("/api/v1/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [SkippableFact]
    public async Task Register_then_read_and_update_profile()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();

        var profile = await client.GetFromJsonAsync<JsonElement>("/api/v1/profile");
        Assert.Equal(JsonValueKind.Null, profile.GetProperty("displayName").ValueKind);

        var update = await client.PutAsJsonAsync("/api/v1/profile",
            new { displayName = "Sam", recoveryGoalType = "Stop", quitOrReductionStartDateUtc = "2026-09-01T00:00:00Z" });
        Assert.Equal(HttpStatusCode.OK, update.StatusCode);
        var updated = await update.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("Sam", updated.GetProperty("displayName").GetString());
        Assert.Equal("Stop", updated.GetProperty("recoveryGoalType").GetString());
    }

    [SkippableFact]
    public async Task Profile_requires_authentication()
    {
        RequireDocker();
        var response = await fixture.CreateClient().GetAsync("/api/v1/profile");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [SkippableFact]
    public async Task Invalid_registration_returns_validation_problem_details()
    {
        RequireDocker();
        var response = await fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest("not-an-email", "short", null));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(problem.GetProperty("errors").TryGetProperty("Email", out _));
        Assert.True(problem.GetProperty("errors").TryGetProperty("Password", out _));
    }

    [SkippableFact]
    public async Task Duplicate_registration_conflicts()
    {
        RequireDocker();
        var email = $"{Guid.NewGuid():N}@example.com";
        await fixture.RegisterAsync(email);
        var response = await fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(email.ToUpperInvariant(), "correct horse", null));
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [SkippableFact]
    public async Task Login_refresh_and_reuse_detection()
    {
        RequireDocker();
        var email = $"{Guid.NewGuid():N}@example.com";
        await fixture.RegisterAsync(email);
        var client = fixture.CreateClient();

        var wrong = await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest(email, "wrong password"));
        Assert.Equal(HttpStatusCode.Unauthorized, wrong.StatusCode);

        var login = await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest(email, "correct horse"));
        var first = (await login.Content.ReadFromJsonAsync<AuthResponse>())!;

        var refreshed = await client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken));
        Assert.Equal(HttpStatusCode.OK, refreshed.StatusCode);
        var second = (await refreshed.Content.ReadFromJsonAsync<AuthResponse>())!;

        var reuse = await client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, reuse.StatusCode);
        var afterReuse = await client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(second.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, afterReuse.StatusCode);
    }

    [SkippableFact]
    public async Task Deleted_account_access_token_stops_working_immediately()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();

        var delete = await client.DeleteAsync("/api/v1/auth/account");
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);

        var profile = await client.GetAsync("/api/v1/profile");
        Assert.Equal(HttpStatusCode.Unauthorized, profile.StatusCode);
    }

    [SkippableFact]
    public async Task Logout_revokes_the_refresh_token()
    {
        RequireDocker();
        var (client, session) = await fixture.RegisterAsync();

        var logout = await client.PostAsJsonAsync("/api/v1/auth/logout", new LogoutRequest(session.RefreshToken));
        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);

        var refresh = await client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(session.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, refresh.StatusCode);
    }
}
