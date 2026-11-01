using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Reclaim.Infrastructure.Persistence;

namespace Reclaim.Api.IntegrationTests;

[Collection(ApiCollection.Name)]
public class JournalApiTests(ReclaimApiFixture fixture)
{
    private void RequireDocker() => Skip.If(fixture.UnavailableReason is not null, fixture.UnavailableReason);

    [SkippableFact]
    public async Task Journal_crud_privacy_and_encrypted_notes()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();
        var (other, _) = await fixture.RegisterAsync();

        var created = await client.PostAsJsonAsync("/api/v1/journal-entries", new
        {
            occurredAtUtc = DateTime.UtcNow.AddHours(-1),
            mood = 2,
            trigger = "Payday",
            urgeIntensity = 4,
            outcome = "Resisted",
            helped = new[] { "TalkedToSomeone" },
            note = "rang my brother instead",
        });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var id = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

        Assert.Equal(HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync("/api/v1/journal-entries", new { occurredAtUtc = DateTime.UtcNow, note = " " })).StatusCode);

        Assert.Equal(0, (await other.GetFromJsonAsync<JsonElement>("/api/v1/journal-entries")).GetProperty("totalCount").GetInt32());
        Assert.Equal(HttpStatusCode.NotFound, (await other.DeleteAsync($"/api/v1/journal-entries/{id}")).StatusCode);

        await using (var scope = fixture.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ReclaimDbContext>();
            var stored = await db.Database.SqlQuery<string>($"SELECT \"Note\" AS \"Value\" FROM \"JournalEntry\" WHERE \"Id\" = {id}").SingleAsync();
            Assert.DoesNotContain("brother", stored);
        }

        var updated = await client.PutAsJsonAsync($"/api/v1/journal-entries/{id}", new { occurredAtUtc = DateTime.UtcNow.AddHours(-1), mood = 4 });
        Assert.Equal(4, (await updated.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("mood").GetInt32());
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/api/v1/journal-entries/{id}")).StatusCode);
    }

    [SkippableFact]
    public async Task Insights_combine_journal_urges_and_urge_sessions()
    {
        RequireDocker();
        var (client, _) = await fixture.RegisterAsync();

        // Four "I feel like gambling" sessions and one journal urge, all at 21:00 South African time (19:00 UTC).
        var evening = DateTime.UtcNow.Date.AddDays(-1).AddHours(19);
        for (var i = 1; i <= 4; i++)
        {
            var urge = await (await client.PostAsJsonAsync("/api/v1/urges",
                new { trigger = "Boredom", coolingOffMinutes = 10, startedAtUtc = evening.AddDays(-i) })).Content.ReadFromJsonAsync<JsonElement>();
            await client.PutAsJsonAsync($"/api/v1/urges/{urge.GetProperty("id").GetGuid()}/resolve",
                new { outcome = "Passed", resolvedAtUtc = evening.AddDays(-i).AddMinutes(12) });
        }

        var tooFew = await client.GetFromJsonAsync<JsonElement>("/api/v1/journal-entries/insights");
        Assert.Equal(0, tooFew.GetProperty("insights").GetArrayLength());
        Assert.Equal(4, tooFew.GetProperty("urgesRecorded").GetInt32());

        await client.PostAsJsonAsync("/api/v1/journal-entries", new { occurredAtUtc = evening, urgeIntensity = 3, outcome = "Resisted" });
        var insights = await client.GetFromJsonAsync<JsonElement>("/api/v1/journal-entries/insights");
        var texts = insights.GetProperty("insights").EnumerateArray().Select(t => t.GetString()).ToList();
        Assert.Contains("All of your recorded urges happened between 19:00 and 22:00.", texts);
        Assert.Contains("not a diagnosis", insights.GetProperty("disclaimer").GetString());

        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync("/api/v1/journal-entries/insights?timeZone=Mars/Olympus")).StatusCode);
    }
}
