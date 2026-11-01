using Reclaim.Application.Dashboard;
using Reclaim.Domain.Common;
using Reclaim.Domain.Content;
using Reclaim.Domain.Gambling;
using Reclaim.Domain.Goals;
using Reclaim.Domain.Onboarding;
using Reclaim.Domain.Urges;

namespace Reclaim.Application.Tests;

public class RecoveryMathsTests
{
    private static readonly DateOnly Start = new(2026, 10, 1);
    private static DateOnly Oct(int day) => new(2026, 10, day);

    // Mirrors mobile/test/features/dashboard/dashboard_test.dart so both sides agree.
    [Fact]
    public void Day_one_with_nothing_logged_is_a_one_day_run() =>
        Assert.Equal(new StreakSummary(1, 1, 1), RecoveryMaths.Streaks(Start, [], Oct(1)));

    [Fact]
    public void Gambling_today_resets_the_current_run_but_keeps_the_longest() =>
        Assert.Equal(new StreakSummary(0, 9, 10), RecoveryMaths.Streaks(Start, [Oct(10)], Oct(10)));

    [Fact]
    public void Current_run_counts_from_the_day_after_the_last_gambling_day() =>
        Assert.Equal(new StreakSummary(9, 16, 29), RecoveryMaths.Streaks(Start, [Oct(3), Oct(3), Oct(20)], Oct(29)));

    [Fact]
    public void History_from_before_the_journey_does_not_count() =>
        Assert.Equal(new StreakSummary(5, 5, 5), RecoveryMaths.Streaks(Start, [new DateOnly(2026, 9, 28)], Oct(5)));

    [Fact]
    public void Money_kept_is_usual_spend_over_the_journey_minus_losses()
    {
        Assert.Equal(1000m, RecoveryMaths.EstimatedMoneyKept(3650m, 10, 200m));
        Assert.Equal(0m, RecoveryMaths.EstimatedMoneyKept(100m, 1, 999m));
        Assert.Equal(1200m, RecoveryMaths.EstimatedMoneyKept(3650m, 10, -500m));
        Assert.Null(RecoveryMaths.EstimatedMoneyKept(null, 10, 0));
        Assert.Null(RecoveryMaths.EstimatedMoneyKept(0, 10, 0));
    }
}

public class UrgeAndGoalDomainTests
{
    private static readonly DateTime Now = new(2026, 10, 29, 20, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Urge_extends_and_resolves_once()
    {
        var urge = Urge.Start(null, Guid.NewGuid(), TriggerType.Payday, 4, 20, Now, Now);
        urge.Extend(Now);
        Assert.Equal(30, urge.CoolingOffMinutes);

        urge.Resolve(UrgeOutcome.Passed, "  went for a walk ", Now.AddMinutes(31), Now);
        Assert.Equal("went for a walk", urge.Notes);
        Assert.Throws<DomainException>(() => urge.Resolve(UrgeOutcome.Gambled, null, Now, Now));
        Assert.Throws<DomainException>(() => urge.Extend(Now));
    }

    [Theory]
    [InlineData(7, null)]
    [InlineData(10, 6)]
    public void Urge_rejects_unsupported_pause_or_intensity(int minutes, int? intensity) =>
        Assert.Throws<DomainException>(() => Urge.Start(null, Guid.NewGuid(), TriggerType.Stress, intensity, minutes, Now, Now));

    [Fact]
    public void Urge_cannot_end_before_it_started()
    {
        var urge = Urge.Start(null, Guid.NewGuid(), TriggerType.Stress, null, 10, Now, Now);
        Assert.Throws<DomainException>(() => urge.Resolve(UrgeOutcome.Passed, null, Now.AddMinutes(-1), Now));
    }

    [Fact]
    public void Goal_tracks_contributions()
    {
        var goal = RecoveryGoal.Create(null, Guid.NewGuid(), " Car deposit ", GoalCategory.Car, 20000m, null, Now);
        var first = goal.AddContribution(null, 500m, ContributionSource.Manual, Now, Now);
        goal.AddContribution(null, 1200m, ContributionSource.EstimatedSavings, Now, Now);
        Assert.Equal("Car deposit", goal.Name);
        Assert.Equal(1700m, goal.SavedAmount);

        goal.RemoveContribution(first.Id, Now);
        Assert.Equal(1200m, goal.SavedAmount);
        Assert.Throws<DomainException>(() => goal.AddContribution(null, 0.001m, ContributionSource.Manual, Now, Now));
        Assert.Throws<DomainException>(() => RecoveryGoal.Create(null, Guid.NewGuid(), " ", GoalCategory.Car, 1m, null, Now));
    }

    [Theory]
    [InlineData("Betway.co.za", "betway.co.za")]
    [InlineData("https://www.betway.co.za/sport?x=1", "betway.co.za")]
    [InlineData("sub.example.com.", "sub.example.com")]
    public void Blocklist_domains_are_normalised(string input, string expected) =>
        Assert.Equal(expected, BlocklistDomain.Normalize(input));

    [Theory]
    [InlineData("localhost")]
    [InlineData("bad domain.com")]
    [InlineData("-bad.com")]
    [InlineData("")]
    public void Invalid_blocklist_domains_are_rejected(string input) =>
        Assert.Throws<DomainException>(() => BlocklistDomain.Normalize(input));

    [Fact]
    public void Support_resource_needs_a_way_to_reach_it_and_starts_unverified()
    {
        Assert.Throws<DomainException>(() => SupportResource.Create("X", SupportCategory.Counselling, "Y", null, null, "South Africa", Now));
        var resource = SupportResource.Create("X", SupportCategory.Counselling, "Y", null, "https://example.org", "South Africa", Now);
        Assert.False(resource.IsVerified);
        resource.MarkVerified(Now);
        Assert.True(resource.IsVerified);
    }

    [Fact]
    public void Gambling_type_enum_stays_in_step_with_mobile()
    {
        // The mobile app mirrors these members by name (camelCase); see mobile/lib/features/onboarding/domain.
        Assert.Equal(["SportsBetting", "Casino", "Slots", "CrashGame", "Lottery", "Other"], Enum.GetNames<GamblingType>());
    }
}
