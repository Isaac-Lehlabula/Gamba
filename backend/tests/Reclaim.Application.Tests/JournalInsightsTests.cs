using Reclaim.Application.Journal;
using Reclaim.Domain.Common;
using Reclaim.Domain.Journal;
using Reclaim.Domain.Onboarding;

namespace Reclaim.Application.Tests;

/// <summary>Same cases as mobile/test/features/journal/journal_test.dart, so both sides agree.</summary>
public class JournalInsightsTests
{
    /// <summary>Thursday 29 October 2026 at <paramref name="hour"/>:00, <paramref name="daysAgo"/> days earlier.</summary>
    private static DateTime At(int hour, int daysAgo = 0) => new DateTime(2026, 10, 29, hour, 0, 0).AddDays(-daysAgo);

    private static UrgeEvent Urge(DateTime when, TriggerType? trigger = null, bool? gambled = null, params CopingStrategy[] helped) =>
        new(when, trigger, gambled, helped);

    [Fact]
    public void Nothing_is_said_until_there_are_enough_urges() =>
        Assert.Empty(JournalInsights.Describe([.. Enumerable.Range(0, 4).Select(i => Urge(At(21, i), TriggerType.Payday))]));

    [Fact]
    public void Clustered_time_of_day_uses_actual_counts() =>
        Assert.Contains("4 of 5 of your recorded urges happened between 20:00 and 23:00.",
            JournalInsights.Describe([Urge(At(20, 1)), Urge(At(21, 2)), Urge(At(22, 3)), Urge(At(21, 4)), Urge(At(9, 5))]));

    [Fact]
    public void Window_can_wrap_past_midnight() =>
        Assert.Contains("between 22:00 and 01:00",
            JournalInsights.Describe([.. Enumerable.Range(0, 5).Select(i => Urge(At(i % 2 == 0 ? 23 : 0, i)))])[0]);

    [Fact]
    public void Weekday_trigger_and_what_helped()
    {
        var fridays = Enumerable.Range(0, 4).Select(w => new DateTime(2026, 10, 2 + 7 * w, 12, 0, 0));
        List<UrgeEvent> events =
        [
            .. fridays.Select(f => Urge(f, TriggerType.Payday, false, CopingStrategy.Walked)),
            Urge(new DateTime(2026, 10, 5, 8, 0, 0), TriggerType.Boredom, true),
            Urge(new DateTime(2026, 10, 6, 15, 0, 0), TriggerType.Stress, false, CopingStrategy.Breathing),
            Urge(new DateTime(2026, 10, 7, 18, 0, 0)),
        ];
        var texts = JournalInsights.Describe(events);
        Assert.Contains("Urges came up most often on Fridays (4 of 7).", texts);
        Assert.Contains("\"Payday\" was the trigger you recorded most (4 of 6 times).", texts);
        Assert.Contains("\"Went for a walk or moved\" was part of 4 of the times you got through an urge.", texts);
    }

    [Fact]
    public void Journal_entries_need_something_in_them_and_valid_scales()
    {
        var now = new DateTime(2026, 10, 29, 20, 0, 0, DateTimeKind.Utc);
        Assert.Throws<DomainException>(() => JournalEntry.Create(null, Guid.NewGuid(), now, null, null, null, null, [], "  ", now));
        Assert.Throws<DomainException>(() => JournalEntry.Create(null, Guid.NewGuid(), now, 6, null, null, null, [], null, now));
        Assert.Throws<DomainException>(() => JournalEntry.Create(null, Guid.NewGuid(), now.AddHours(1), 3, null, null, null, [], null, now));

        var entry = JournalEntry.Create(null, Guid.NewGuid(), now, null, TriggerType.Payday, 4, JournalOutcome.Resisted,
            [CopingStrategy.LeftPhone, CopingStrategy.Walked, CopingStrategy.Walked], " rang my brother ", now);
        Assert.Equal([CopingStrategy.Walked, CopingStrategy.LeftPhone], entry.Helped);
        Assert.Equal("rang my brother", entry.Note);
        Assert.True(entry.HadUrge);
    }
}
