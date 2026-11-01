using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Application.GamblingEntries;
using Reclaim.Domain.Gambling;

namespace Reclaim.Application.Dashboard;

public sealed record StreakSummary(int Current, int Longest, int JourneyDay);

public sealed record GoalSnapshot(Guid Id, string Name, decimal TargetAmount, decimal SavedAmount);

public sealed record DashboardSummaryResponse(
    string TimeZone,
    DateTime? JourneyStartUtc,
    StreakSummary? Streaks,
    GamblingTotals ThisMonth,
    decimal? UsualMonthlySpend,
    decimal? EstimatedMoneyKept,
    IReadOnlyList<GoalSnapshot> Goals);

/// <summary>
/// Same rules as the mobile app (mobile/lib/features/dashboard/domain/dashboard.dart), computed
/// from source records; client-computed streaks or totals are never trusted.
/// </summary>
public static class RecoveryMaths
{
    /// <summary>Runs of calendar days without gambling, from <paramref name="start"/> to <paramref name="today"/> inclusive.</summary>
    public static StreakSummary Streaks(DateOnly start, IEnumerable<DateOnly> gamblingDays, DateOnly today)
    {
        if (today < start) return new(0, 0, 0);

        var longest = 0;
        var runStart = start;
        foreach (var day in gamblingDays.Where(d => d >= start && d <= today).Distinct().Order())
        {
            longest = Math.Max(longest, day.DayNumber - runStart.DayNumber);
            runStart = day.AddDays(1);
        }
        var current = runStart > today ? 0 : today.DayNumber - runStart.DayNumber + 1;
        return new(current, Math.Max(longest, current), today.DayNumber - start.DayNumber + 1);
    }

    /// <summary>Usual monthly spend spread over the journey, minus net loss since starting; never negative.</summary>
    public static decimal? EstimatedMoneyKept(decimal? usualMonthlySpend, int journeyDays, decimal netLossSinceStart)
    {
        if (usualMonthlySpend is not > 0 || journeyDays <= 0) return null;
        var expected = decimal.Round(usualMonthlySpend.Value * 12 * journeyDays / 365, 2);
        return Math.Max(0, expected - Math.Max(0, netLossSinceStart));
    }
}

public sealed class GetDashboardSummaryHandler(
    IUserProfileRepository profiles,
    IOnboardingResponseRepository onboarding,
    IGamblingActivityReader activity,
    IUrgeRepository urges,
    IGoalRepository goals,
    TimeProvider time)
{
    public async Task<DashboardSummaryResponse> HandleAsync(Guid appUserId, string? timeZone, CancellationToken ct = default)
    {
        if (!StatsPeriods.TryFindZone(timeZone, out var zone))
            throw new FluentValidation.ValidationException([new FluentValidation.Results.ValidationFailure("timeZone", "Unknown time zone.")]);

        var profile = await profiles.GetByAppUserIdAsync(appUserId, ct) ?? throw new NotFoundException("Profile not found.");
        var entries = await activity.GetActivityAsync(profile.Id, ct);
        var nowUtc = time.GetUtcNow().UtcDateTime;
        DateOnly LocalDay(DateTime utc) => DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(utc, zone));

        var (_, _, monthStartUtc) = StatsPeriods.Starts(nowUtc, zone);
        var thisMonth = GamblingTotals.From(Sum(entries.Where(e => e.OccurredAtUtc >= monthStartUtc)));
        var spend = (await onboarding.GetLatestAsync(profile.Id, ct))?.ApproxMonthlySpend;

        StreakSummary? streaks = null;
        decimal? kept = null;
        if (profile.QuitOrReductionStartDateUtc is { } startUtc)
        {
            var start = LocalDay(startUtc);
            var gamblingDays = entries.Where(e => e.Type != GamblingEntryType.Withdrawal).Select(e => LocalDay(e.OccurredAtUtc))
                .Concat((await urges.GetGambledDatesAsync(profile.Id, ct)).Select(LocalDay));
            streaks = RecoveryMaths.Streaks(start, gamblingDays, LocalDay(nowUtc));
            var sinceStart = GamblingTotals.From(Sum(entries.Where(e => LocalDay(e.OccurredAtUtc) >= start)));
            kept = RecoveryMaths.EstimatedMoneyKept(spend, streaks.JourneyDay, sinceStart.NetLoss);
        }

        var goalSnapshots = (await goals.ListAsync(profile.Id, ct))
            .Select(g => new GoalSnapshot(g.Id, g.Name, g.TargetAmount, g.SavedAmount)).ToList();

        return new(zone.Id, profile.QuitOrReductionStartDateUtc, streaks, thisMonth, spend, kept, goalSnapshots);
    }

    private static Dictionary<GamblingEntryType, decimal> Sum(IEnumerable<EntryActivity> entries) =>
        entries.GroupBy(e => e.Type).ToDictionary(g => g.Key, g => g.Sum(e => e.Amount));
}
