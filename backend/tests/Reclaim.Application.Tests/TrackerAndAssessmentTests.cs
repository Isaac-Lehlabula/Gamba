using Reclaim.Application.Assessment;
using Reclaim.Application.GamblingEntries;
using Reclaim.Domain.Assessment;
using Reclaim.Domain.Common;
using Reclaim.Domain.Gambling;

namespace Reclaim.Application.Tests;

public class AssessmentTests
{
    private static Dictionary<string, int> AnswersTotalling(int total)
    {
        var answers = AssessmentQuestionnaire.Questions.ToDictionary(q => q.Id, _ => 0);
        foreach (var q in AssessmentQuestionnaire.Questions)
        {
            var take = Math.Min(AssessmentQuestionnaire.MaxAnswer, total);
            answers[q.Id] = take;
            total -= take;
        }
        return answers;
    }

    [Theory]
    [InlineData(0, RiskLevel.Low)]
    [InlineData(4, RiskLevel.Low)]
    [InlineData(5, RiskLevel.Increasing)]
    [InlineData(12, RiskLevel.Increasing)]
    [InlineData(13, RiskLevel.High)]
    [InlineData(27, RiskLevel.High)]
    public void Score_maps_to_risk_level(int total, RiskLevel expected)
    {
        var result = SelfAssessmentResult.Submit(null, Guid.NewGuid(), AnswersTotalling(total), DateTime.UtcNow);
        Assert.Equal(total, result.Score);
        Assert.Equal(expected, result.RiskLevel);
    }

    [Fact]
    public void Incomplete_answers_are_rejected()
    {
        var answers = AnswersTotalling(3);
        answers.Remove(AssessmentQuestionnaire.Questions[0].Id);
        Assert.Throws<DomainException>(() => AssessmentQuestionnaire.Score(answers));
        Assert.False(new SubmitAssessmentRequestValidator().Validate(new SubmitAssessmentRequest(null, answers)).IsValid);
    }

    [Fact]
    public void Out_of_range_answers_are_rejected()
    {
        var answers = AnswersTotalling(0);
        answers[AssessmentQuestionnaire.Questions[0].Id] = 4;
        Assert.Throws<DomainException>(() => AssessmentQuestionnaire.Score(answers));
        Assert.False(new SubmitAssessmentRequestValidator().Validate(new SubmitAssessmentRequest(null, answers)).IsValid);
    }

    [Fact]
    public void Unknown_question_ids_are_rejected()
    {
        var answers = AnswersTotalling(0);
        answers.Remove(AssessmentQuestionnaire.Questions[0].Id);
        answers["made-up"] = 0;
        Assert.False(new SubmitAssessmentRequestValidator().Validate(new SubmitAssessmentRequest(null, answers)).IsValid);
    }

    [Theory]
    [InlineData(RiskLevel.Low)]
    [InlineData(RiskLevel.Increasing)]
    [InlineData(RiskLevel.High)]
    public void Every_level_has_guidance_and_avoids_shaming_language(RiskLevel level)
    {
        var (summary, actions) = AssessmentGuidance.For(level);
        Assert.NotEmpty(actions);
        foreach (var text in actions.SelectMany(a => new[] { a.Title, a.Description }).Append(summary))
        {
            Assert.DoesNotContain("addict", text, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("fail", text, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void Result_always_carries_the_non_diagnostic_disclaimer()
    {
        var result = SelfAssessmentResult.Submit(null, Guid.NewGuid(), AnswersTotalling(20), DateTime.UtcNow);
        Assert.Contains("not a medical diagnosis", AssessmentResultResponse.From(result).Disclaimer);
    }
}

public class GamblingEntryTests
{
    private static readonly DateTime Now = new(2026, 10, 29, 12, 0, 0, DateTimeKind.Utc);

    private static GamblingEntry Create(decimal amount = 100m, DateTime? occurred = null, string? notes = null, GamblingPlatform? platform = null, Guid? profileId = null) =>
        GamblingEntry.Create(null, profileId ?? Guid.NewGuid(), GamblingEntryType.Deposit, amount, occurred ?? Now, GamblingType.SportsBetting, platform, notes, Now);

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    [InlineData(10.005)]
    [InlineData(10_000_000.01)]
    public void Invalid_amounts_are_rejected(decimal amount) => Assert.Throws<DomainException>(() => Create(amount));

    [Fact]
    public void Future_dates_beyond_clock_skew_are_rejected()
    {
        Create(occurred: Now.AddMinutes(5));
        Assert.Throws<DomainException>(() => Create(occurred: Now.AddHours(1)));
    }

    [Fact]
    public void Notes_are_trimmed_and_blank_notes_dropped()
    {
        Assert.Equal("lost on the late game", Create(notes: "  lost on the late game ").Notes);
        Assert.Null(Create(notes: "   ").Notes);
        Assert.Throws<DomainException>(() => Create(notes: new string('x', GamblingEntry.MaxNotesLength + 1)));
    }

    [Fact]
    public void Platform_from_another_profile_is_rejected()
    {
        var someoneElses = GamblingPlatform.CreateForProfile(Guid.NewGuid(), "Betway", Now);
        Assert.Throws<DomainException>(() => Create(platform: someoneElses));
    }

    [Fact]
    public void Platform_names_normalise_case_and_whitespace()
    {
        Assert.Equal(GamblingPlatform.Normalize("Betway"), GamblingPlatform.Normalize("  betway "));
        Assert.Equal("Betway", GamblingPlatform.CreateForProfile(Guid.NewGuid(), " Betway ", Now).Name);
    }

    [Fact]
    public void Client_supplied_id_is_kept()
    {
        var id = Guid.NewGuid();
        var entry = GamblingEntry.Create(id, Guid.NewGuid(), GamblingEntryType.Loss, 1m, Now, GamblingType.Casino, null, null, Now);
        Assert.Equal(id, entry.Id);
    }
}

public class GamblingStatsTests
{
    [Fact]
    public void Net_loss_combines_money_moved_and_outcomes()
    {
        var totals = GamblingTotals.From(new Dictionary<GamblingEntryType, decimal>
        {
            [GamblingEntryType.Deposit] = 500m,
            [GamblingEntryType.Withdrawal] = 150m,
            [GamblingEntryType.Loss] = 80m,
            [GamblingEntryType.Win] = 30m,
        });
        Assert.Equal(400m, totals.NetLoss);
    }

    [Fact]
    public void Missing_types_count_as_zero()
    {
        var totals = GamblingTotals.From(new Dictionary<GamblingEntryType, decimal>());
        Assert.Equal(new GamblingTotals(0, 0, 0, 0, 0), totals);
    }

    [Fact]
    public void Periods_follow_south_african_local_time()
    {
        Assert.True(StatsPeriods.TryFindZone(null, out var zone));

        // Thursday 29 Oct 2026, 23:30 in Johannesburg (UTC+2).
        var (today, week, month) = StatsPeriods.Starts(new DateTime(2026, 10, 29, 21, 30, 0, DateTimeKind.Utc), zone);
        Assert.Equal(new DateTime(2026, 10, 28, 22, 0, 0, DateTimeKind.Utc), today);
        Assert.Equal(new DateTime(2026, 10, 25, 22, 0, 0, DateTimeKind.Utc), week); // Monday 26 Oct
        Assert.Equal(new DateTime(2026, 9, 30, 22, 0, 0, DateTimeKind.Utc), month);
    }

    [Fact]
    public void Just_after_local_midnight_is_a_new_day()
    {
        StatsPeriods.TryFindZone("Africa/Johannesburg", out var zone);
        var (today, _, _) = StatsPeriods.Starts(new DateTime(2026, 10, 29, 22, 30, 0, DateTimeKind.Utc), zone);
        Assert.Equal(new DateTime(2026, 10, 29, 22, 0, 0, DateTimeKind.Utc), today);
    }

    [Fact]
    public void Unknown_time_zone_is_reported()
    {
        Assert.False(StatsPeriods.TryFindZone("Mars/Olympus_Mons", out _));
    }
}
