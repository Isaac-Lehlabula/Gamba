using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Reclaim.Application.Common;
using Reclaim.Application.GamblingEntries;
using Reclaim.Domain.Assessment;
using Reclaim.Infrastructure.Persistence;

namespace Reclaim.Api.IntegrationTests;

[Collection(ApiCollection.Name)]
public class OnboardingAndAssessmentApiTests(ReclaimApiFixture fixture)
{
    private void RequireDocker() => Skip.If(fixture.UnavailableReason is not null, fixture.UnavailableReason);

    [SkippableFact]
    public async Task Onboarding_submit_and_read_latest()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();

        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync("/api/v1/onboarding-responses")).StatusCode);

        var submit = await client.PostAsJsonAsync("/api/v1/onboarding-responses", new
        {
            gamblingTypes = new[] { "SportsBetting", "CrashGame", "SportsBetting" },
            frequencyBand = "SeveralTimesAWeek",
            approxMonthlySpend = 2500.00m,
            triggers = new[] { "Payday", "Boredom" },
            goal = "Stop",
            moneyGoalPreference = "Car deposit",
        });
        Assert.Equal(HttpStatusCode.Created, submit.StatusCode);

        var latest = await client.GetFromJsonAsync<JsonElement>("/api/v1/onboarding-responses");
        Assert.Equal(2, latest.GetProperty("gamblingTypes").GetArrayLength());
        Assert.Equal("Car deposit", latest.GetProperty("moneyGoalPreference").GetString());
        Assert.Equal("SeveralTimesAWeek", latest.GetProperty("frequencyBand").GetString());
    }

    [SkippableFact]
    public async Task Onboarding_requires_frequency_and_goal()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var response = await client.PostAsJsonAsync("/api/v1/onboarding-responses", new { gamblingTypes = Array.Empty<string>(), triggers = Array.Empty<string>() });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var errors = (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("errors");
        Assert.True(errors.TryGetProperty("FrequencyBand", out _));
        Assert.True(errors.TryGetProperty("Goal", out _));
    }

    [SkippableFact]
    public async Task Questions_are_available_without_an_account()
    {
        RequireDocker();
        var questions = await fixture.CreateClient().GetFromJsonAsync<JsonElement>("/api/v1/assessment/questions");
        Assert.Equal(AssessmentQuestionnaire.Questions.Count, questions.GetProperty("questions").GetArrayLength());
        Assert.Equal(4, questions.GetProperty("answerOptions").GetArrayLength());
    }

    [SkippableFact]
    public async Task Assessment_is_scored_server_side_and_kept_in_history()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var answers = AssessmentQuestionnaire.Questions.ToDictionary(q => q.Id, _ => 3);

        var submit = await client.PostAsJsonAsync("/api/v1/assessment/submit", new { answers, score = 0, riskLevel = "Low" });
        Assert.Equal(HttpStatusCode.Created, submit.StatusCode);
        var result = await submit.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(27, result.GetProperty("score").GetInt32());
        Assert.Equal("High", result.GetProperty("riskLevel").GetString());
        Assert.NotEqual(0, result.GetProperty("recommendedActions").GetArrayLength());

        await client.PostAsJsonAsync("/api/v1/assessment/submit", new { answers = AssessmentQuestionnaire.Questions.ToDictionary(q => q.Id, _ => 0) });
        var history = await client.GetFromJsonAsync<JsonElement>("/api/v1/assessment/history");
        Assert.Equal(2, history.GetProperty("totalCount").GetInt32());
        Assert.Equal("Low", history.GetProperty("items")[0].GetProperty("riskLevel").GetString());
    }

    [SkippableFact]
    public async Task Incomplete_assessment_is_rejected()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var response = await client.PostAsJsonAsync("/api/v1/assessment/submit", new { answers = new Dictionary<string, int> { ["chased-losses"] = 2 } });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}

[Collection(ApiCollection.Name)]
public class GamblingEntriesApiTests(ReclaimApiFixture fixture)
{
    private void RequireDocker() => Skip.If(fixture.UnavailableReason is not null, fixture.UnavailableReason);

    private static object Entry(string type, decimal amount, DateTime occurred, string? platform = null, string? notes = null, Guid? id = null) =>
        new { id, entryType = type, amount, occurredAtUtc = occurred, gamblingType = "SportsBetting", platformName = platform, notes };

    private static async Task<GamblingEntryResponse> CreateAsync(HttpClient client, object entry)
    {
        var response = await client.PostAsJsonAsync("/api/v1/gambling-entries", entry);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<GamblingEntryResponse>(ReclaimApiFixture.Json))!;
    }

    [SkippableFact]
    public async Task Create_list_update_and_delete()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var now = DateTime.UtcNow;

        var first = await CreateAsync(client, Entry("Deposit", 200m, now.AddDays(-2), "Betway "));
        var second = await CreateAsync(client, Entry("Loss", 75.50m, now.AddDays(-1), "betway"));
        await CreateAsync(client, Entry("Deposit", 50m, now, "Other place"));
        Assert.Equal("Betway", second.PlatformName);

        var byPlatform = await client.GetFromJsonAsync<PagedResponse<GamblingEntryResponse>>("/api/v1/gambling-entries?platform=BETWAY", ReclaimApiFixture.Json);
        Assert.Equal(2, byPlatform!.TotalCount);
        Assert.Equal(second.Id, byPlatform.Items[0].Id); // newest first

        var page = await client.GetFromJsonAsync<PagedResponse<GamblingEntryResponse>>("/api/v1/gambling-entries?entryType=Deposit&pageSize=1", ReclaimApiFixture.Json);
        Assert.Equal(2, page!.TotalCount);
        Assert.Single(page.Items);

        var update = await client.PutAsJsonAsync($"/api/v1/gambling-entries/{first.Id}", Entry("Withdrawal", 120m, now.AddDays(-2), null, "cashed out"));
        Assert.Equal(HttpStatusCode.OK, update.StatusCode);
        var updated = (await update.Content.ReadFromJsonAsync<GamblingEntryResponse>(ReclaimApiFixture.Json))!;
        Assert.Null(updated.PlatformName);
        Assert.Equal("cashed out", updated.Notes);

        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/api/v1/gambling-entries/{first.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.DeleteAsync($"/api/v1/gambling-entries/{first.Id}")).StatusCode);
    }

    [SkippableFact]
    public async Task Entries_are_private_to_their_owner()
    {
        RequireDocker();
        var (owner, _) = await fixture.RegisterAsync();
        var (other, _) = await fixture.RegisterAsync();
        var entry = await CreateAsync(owner, Entry("Deposit", 100m, DateTime.UtcNow, "Betway"));

        var list = await other.GetFromJsonAsync<PagedResponse<GamblingEntryResponse>>("/api/v1/gambling-entries", ReclaimApiFixture.Json);
        Assert.Equal(0, list!.TotalCount);
        Assert.Equal(HttpStatusCode.NotFound,
            (await other.PutAsJsonAsync($"/api/v1/gambling-entries/{entry.Id}", Entry("Loss", 1m, DateTime.UtcNow))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await other.DeleteAsync($"/api/v1/gambling-entries/{entry.Id}")).StatusCode);
    }

    [SkippableFact]
    public async Task Notes_are_encrypted_at_rest()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var entry = await CreateAsync(client, Entry("Loss", 300m, DateTime.UtcNow, notes: "after payday, at the tavern"));

        await using var scope = fixture.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<ReclaimDbContext>();
        var stored = await db.Database
            .SqlQuery<string>($"SELECT \"Notes\" AS \"Value\" FROM \"GamblingEntry\" WHERE \"Id\" = {entry.Id}")
            .SingleAsync();

        Assert.StartsWith("enc:test:", stored);
        Assert.DoesNotContain("tavern", stored);
        Assert.Equal("after payday, at the tavern", entry.Notes);
    }

    [SkippableFact]
    public async Task Invalid_entries_are_rejected()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();

        var future = await client.PostAsJsonAsync("/api/v1/gambling-entries", Entry("Deposit", 10m, DateTime.UtcNow.AddDays(2)));
        Assert.Equal(HttpStatusCode.BadRequest, future.StatusCode);

        var tooPrecise = await client.PostAsJsonAsync("/api/v1/gambling-entries", Entry("Deposit", 10.001m, DateTime.UtcNow));
        Assert.Equal(HttpStatusCode.BadRequest, tooPrecise.StatusCode);

        var missingType = await client.PostAsJsonAsync("/api/v1/gambling-entries", new { amount = 10m, occurredAtUtc = DateTime.UtcNow, gamblingType = "Casino" });
        Assert.Equal(HttpStatusCode.BadRequest, missingType.StatusCode);
    }

    [SkippableFact]
    public async Task Reusing_a_client_id_conflicts()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var id = Guid.NewGuid();
        var created = await CreateAsync(client, Entry("Deposit", 10m, DateTime.UtcNow, id: id));
        Assert.Equal(id, created.Id);

        var again = await client.PostAsJsonAsync("/api/v1/gambling-entries", Entry("Deposit", 10m, DateTime.UtcNow, id: id));
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);
    }

    [SkippableFact]
    public async Task Stats_total_by_period()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var now = DateTime.UtcNow;
        await CreateAsync(client, Entry("Deposit", 500m, now.AddMinutes(-1)));
        await CreateAsync(client, Entry("Withdrawal", 100m, now.AddMinutes(-1)));
        await CreateAsync(client, Entry("Loss", 50m, now.AddDays(-60)));

        var stats = (await client.GetFromJsonAsync<GamblingStatsResponse>("/api/v1/gambling-entries/stats", ReclaimApiFixture.Json))!;
        Assert.Equal("Africa/Johannesburg", stats.TimeZone);
        Assert.Equal(new GamblingTotals(500m, 100m, 0m, 0m, 400m), stats.Today);
        Assert.Equal(400m, stats.ThisMonth.NetLoss);
        Assert.Equal(new GamblingTotals(500m, 100m, 0m, 50m, 450m), stats.Lifetime);

        var badZone = await client.GetAsync("/api/v1/gambling-entries/stats?timeZone=Mars/Olympus_Mons");
        Assert.Equal(HttpStatusCode.BadRequest, badZone.StatusCode);
    }
}
