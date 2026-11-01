using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Reclaim.Domain.Content;
using Reclaim.Infrastructure.Jobs;
using Reclaim.Infrastructure.Persistence;

namespace Reclaim.Api.IntegrationTests;

[Collection(ApiCollection.Name)]
public class RecoveryApiTests(ReclaimApiFixture fixture)
{
    private void RequireDocker() => Skip.If(fixture.UnavailableReason is not null, fixture.UnavailableReason);

    private static async Task<JsonElement> Json(HttpResponseMessage response) => await response.Content.ReadFromJsonAsync<JsonElement>();

    [SkippableFact]
    public async Task Urge_start_extend_resolve_and_list()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();

        var start = await client.PostAsJsonAsync("/api/v1/urges", new { trigger = "Payday", intensity = 4, coolingOffMinutes = 20 });
        Assert.Equal(HttpStatusCode.Created, start.StatusCode);
        var id = (await Json(start)).GetProperty("id").GetGuid();

        var extended = await Json(await client.PutAsync($"/api/v1/urges/{id}/extend", null));
        Assert.Equal(30, extended.GetProperty("coolingOffMinutes").GetInt32());

        var resolve = await client.PutAsJsonAsync($"/api/v1/urges/{id}/resolve", new { outcome = "Passed", notes = "called my sister" });
        Assert.Equal("Passed", (await Json(resolve)).GetProperty("outcome").GetString());

        var again = await client.PutAsJsonAsync($"/api/v1/urges/{id}/resolve", new { outcome = "Gambled" });
        Assert.Equal(HttpStatusCode.BadRequest, again.StatusCode);

        var list = await client.GetFromJsonAsync<JsonElement>("/api/v1/urges");
        Assert.Equal(1, list.GetProperty("totalCount").GetInt32());
        Assert.Equal("called my sister", list.GetProperty("items")[0].GetProperty("notes").GetString());

        var bad = await client.PostAsJsonAsync("/api/v1/urges", new { trigger = "Payday", coolingOffMinutes = 7 });
        Assert.Equal(HttpStatusCode.BadRequest, bad.StatusCode);
    }

    [SkippableFact]
    public async Task Goals_with_contributions_and_privacy()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var (other, _) = await fixture.RegisterAsync();

        var created = await client.PostAsJsonAsync("/api/v1/goals", new { name = "Car deposit", category = "Car", targetAmount = 20000m });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var goalId = (await Json(created)).GetProperty("id").GetGuid();

        var withMoney = await Json(await client.PostAsJsonAsync($"/api/v1/goals/{goalId}/contributions", new { amount = 500m, source = "Manual" }));
        Assert.Equal(500m, withMoney.GetProperty("savedAmount").GetDecimal());
        var contributionId = withMoney.GetProperty("contributions")[0].GetProperty("id").GetGuid();

        // Someone else can neither see nor delete it.
        Assert.Equal(0, (await other.GetFromJsonAsync<JsonElement>("/api/v1/goals")).GetArrayLength());
        Assert.Equal(HttpStatusCode.NotFound, (await other.DeleteAsync($"/api/v1/goals/{goalId}")).StatusCode);

        var removed = await Json(await client.DeleteAsync($"/api/v1/goals/{goalId}/contributions/{contributionId}"));
        Assert.Equal(0m, removed.GetProperty("savedAmount").GetDecimal());

        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/api/v1/goals/{goalId}")).StatusCode);
        Assert.Equal(0, (await client.GetFromJsonAsync<JsonElement>("/api/v1/goals")).GetArrayLength());
    }

    [SkippableFact]
    public async Task Dashboard_summary_is_computed_from_records()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var start = DateTime.UtcNow.AddDays(-9);
        await client.PutAsJsonAsync("/api/v1/profile", new { recoveryGoalType = "Stop", quitOrReductionStartDateUtc = start });
        await client.PostAsJsonAsync("/api/v1/onboarding-responses", new
        {
            gamblingTypes = new[] { "Casino" }, frequencyBand = "Daily", approxMonthlySpend = 3650m, triggers = Array.Empty<string>(), goal = "Stop",
        });
        await client.PostAsJsonAsync("/api/v1/goals", new { name = "Holiday", category = "Holiday", targetAmount = 5000m });

        var summary = await client.GetFromJsonAsync<JsonElement>("/api/v1/dashboard/summary");
        var streaks = summary.GetProperty("streaks");
        Assert.True(streaks.GetProperty("journeyDay").GetInt32() >= 10);
        Assert.Equal(streaks.GetProperty("journeyDay").GetInt32(), streaks.GetProperty("current").GetInt32());
        Assert.True(summary.GetProperty("estimatedMoneyKept").GetDecimal() >= 1200m);
        Assert.Equal("Holiday", summary.GetProperty("goals")[0].GetProperty("name").GetString());

        // A gambled urge today ends the current run.
        var urge = await Json(await client.PostAsJsonAsync("/api/v1/urges", new { trigger = "Boredom", coolingOffMinutes = 10 }));
        await client.PutAsJsonAsync($"/api/v1/urges/{urge.GetProperty("id").GetGuid()}/resolve", new { outcome = "Gambled" });
        var after = await client.GetFromJsonAsync<JsonElement>("/api/v1/dashboard/summary");
        Assert.Equal(0, after.GetProperty("streaks").GetProperty("current").GetInt32());
    }

    [SkippableFact]
    public async Task Blocklist_is_public_seeded_and_supports_incremental_sync()
    {
        RequireDocker();
        var client = fixture.CreateClient();

        var full = await client.GetFromJsonAsync<JsonElement>("/api/v1/blocklist");
        var domains = full.GetProperty("items").EnumerateArray().Select(i => i.GetProperty("domain").GetString()).ToList();
        Assert.Contains("betway.co.za", domains);
        Assert.Equal(BlocklistSeeder.ReadSeed().Count(), domains.Count);
        var nextSince = full.GetProperty("nextSince").GetDateTime();

        var nothingNew = await client.GetFromJsonAsync<JsonElement>($"/api/v1/blocklist?since={nextSince:O}");
        Assert.Equal(0, nothingNew.GetProperty("items").GetArrayLength());

        // A deactivation shows up in the next incremental sync, so clients can unblock too.
        await using (var scope = fixture.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ReclaimDbContext>();
            var row = db.BlocklistDomains.Single(d => d.Domain == "fanduel.com");
            row.SetActive(false, nextSince.AddSeconds(1));
            await db.SaveChangesAsync();
        }
        var changes = await client.GetFromJsonAsync<JsonElement>($"/api/v1/blocklist?since={nextSince:O}");
        var change = Assert.Single(changes.GetProperty("items").EnumerateArray());
        Assert.False(change.GetProperty("isActive").GetBoolean());

        await using (var scope = fixture.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ReclaimDbContext>();
            db.BlocklistDomains.Single(d => d.Domain == "fanduel.com").SetActive(true, DateTime.UtcNow);
            await db.SaveChangesAsync();
        }
    }

    [SkippableFact]
    public async Task Support_resources_only_lists_verified_entries()
    {
        RequireDocker();
        await using (var scope = fixture.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ReclaimDbContext>();
            var now = DateTime.UtcNow;
            db.SupportResources.Add(SupportResource.Create("Unverified line", SupportCategory.GamblingSupport, "Not checked yet", "000", null, "South Africa", now));
            var verified = SupportResource.Create("Checked service", SupportCategory.Counselling, "Checked by a person", null, "https://example.org", "South Africa", now);
            verified.MarkVerified(now);
            db.SupportResources.Add(verified);
            await db.SaveChangesAsync();
        }

        var list = await fixture.CreateClient().GetFromJsonAsync<JsonElement>("/api/v1/support/resources");
        var names = list.EnumerateArray().Select(r => r.GetProperty("name").GetString()).ToList();
        Assert.Contains("Checked service", names);
        Assert.DoesNotContain("Unverified line", names);
    }

    [SkippableFact]
    public async Task Backup_creates_then_updates_without_duplicates()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var entryId = Guid.NewGuid();
        var urgeId = Guid.NewGuid();
        var goalId = Guid.NewGuid();
        var contributionId = Guid.NewGuid();
        var at = DateTime.UtcNow.AddDays(-1);

        object Payload(decimal amount, string? outcome) => new
        {
            profile = new { recoveryGoalType = "Reduce", quitOrReductionStartDateUtc = at.AddDays(-5) },
            onboardingResponses = new[] { new { id = Guid.Parse("11111111-1111-1111-1111-" + entryId.ToString()[^12..]), gamblingTypes = new[] { "Slots" }, frequencyBand = "Weekly", triggers = new[] { "Stress" }, goal = "Reduce" } },
            assessments = Array.Empty<object>(),
            entries = new[] { new { id = entryId, entryType = "Deposit", amount, occurredAtUtc = at, gamblingType = "Slots", platformName = "Betway" } },
            urges = new[] { new { id = urgeId, trigger = "Stress", coolingOffMinutes = 30, startedAtUtc = at, outcome, resolvedAtUtc = outcome is null ? (DateTime?)null : at.AddMinutes(35) } },
            goals = new[] { new { id = goalId, name = "Car", category = "Car", targetAmount = 9000m, contributions = new[] { new { id = contributionId, amount = 100m, source = "Manual", occurredAtUtc = at } } } },
        };

        var first = await Json(await client.PostAsJsonAsync("/api/v1/backup", Payload(200m, null)));
        // Onboarding answers, entry, urge and goal (its contribution comes with it); the profile is updated.
        Assert.Equal(4, first.GetProperty("created").GetInt32());

        var second = await Json(await client.PostAsJsonAsync("/api/v1/backup", Payload(250m, "Passed")));
        Assert.Equal(0, second.GetProperty("created").GetInt32());

        var entries = await client.GetFromJsonAsync<JsonElement>("/api/v1/gambling-entries");
        Assert.Equal(1, entries.GetProperty("totalCount").GetInt32());
        Assert.Equal(250m, entries.GetProperty("items")[0].GetProperty("amount").GetDecimal());

        var urge = (await client.GetFromJsonAsync<JsonElement>("/api/v1/urges")).GetProperty("items")[0];
        Assert.Equal(30, urge.GetProperty("coolingOffMinutes").GetInt32());
        Assert.Equal("Passed", urge.GetProperty("outcome").GetString());

        var goal = (await client.GetFromJsonAsync<JsonElement>("/api/v1/goals"))[0];
        Assert.Equal(100m, goal.GetProperty("savedAmount").GetDecimal());

        // Another account can't claim the same ids.
        var (other, _) = await fixture.RegisterAsync();
        var stolen = await Json(await other.PostAsJsonAsync("/api/v1/backup", Payload(1m, null)));
        Assert.Equal(0, stolen.GetProperty("created").GetInt32());
        Assert.True(stolen.GetProperty("skipped").GetInt32() >= 4);
    }
}
