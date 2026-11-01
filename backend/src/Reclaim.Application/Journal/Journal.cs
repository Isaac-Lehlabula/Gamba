using FluentValidation;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Application.GamblingEntries;
using Reclaim.Domain.Journal;
using Reclaim.Domain.Onboarding;
using Reclaim.Domain.Urges;

namespace Reclaim.Application.Journal;

public interface IJournalRepository
{
    Task<JournalEntry?> GetAsync(Guid id, Guid userProfileId, CancellationToken ct = default);
    Task<bool> ExistsAsync(Guid id, CancellationToken ct = default);
    Task<(IReadOnlyList<JournalEntry> Items, int TotalCount)> GetPageAsync(Guid userProfileId, int page, int pageSize, CancellationToken ct = default);
    Task<IReadOnlyList<JournalEntry>> GetAllAsync(Guid userProfileId, CancellationToken ct = default);

    /// <summary>Urges from the "I feel like gambling" flow that weren't abandoned.</summary>
    Task<IReadOnlyList<Urge>> GetCompletedUrgesAsync(Guid userProfileId, CancellationToken ct = default);
    void Add(JournalEntry entry);
    void Remove(JournalEntry entry);
}

public sealed record SaveJournalEntryRequest(
    Guid? Id,
    DateTime? OccurredAtUtc,
    int? Mood,
    TriggerType? Trigger,
    int? UrgeIntensity,
    JournalOutcome? Outcome,
    List<CopingStrategy>? Helped,
    string? Note);

public sealed record JournalEntryResponse(
    Guid Id,
    DateTime OccurredAtUtc,
    int? Mood,
    TriggerType? Trigger,
    int? UrgeIntensity,
    JournalOutcome? Outcome,
    IReadOnlyList<CopingStrategy> Helped,
    string? Note,
    DateTime UpdatedAtUtc)
{
    public static JournalEntryResponse From(JournalEntry e) =>
        new(e.Id, e.OccurredAtUtc, e.Mood, e.Trigger, e.UrgeIntensity, e.Outcome, e.Helped, e.Note, e.UpdatedAtUtc);
}

public sealed class SaveJournalEntryRequestValidator : AbstractValidator<SaveJournalEntryRequest>
{
    public SaveJournalEntryRequestValidator()
    {
        RuleFor(x => x.OccurredAtUtc).NotNull();
        RuleFor(x => x.Mood).InclusiveBetween(1, 5);
        RuleFor(x => x.UrgeIntensity).InclusiveBetween(1, 5);
        RuleFor(x => x.Trigger).IsInEnum();
        RuleFor(x => x.Outcome).IsInEnum();
        RuleForEach(x => x.Helped).IsInEnum();
        RuleFor(x => x.Note).MaximumLength(JournalEntry.MaxNoteLength);
    }
}

public sealed record UrgeEvent(DateTime LocalTime, TriggerType? Trigger, bool? Gambled, IReadOnlyCollection<CopingStrategy> Helped);

public sealed record JournalInsightsResponse(IReadOnlyList<string> Insights, int UrgesRecorded, int MinimumUrges, string Disclaimer);

/// <summary>
/// Descriptive patterns in what the user recorded. Same rules and wording as the app
/// (mobile/lib/features/journal/domain/insights.dart); keep them in step.
/// </summary>
public static class JournalInsights
{
    public const int MinimumEvents = 5;
    public const string Disclaimer = "These are patterns in what you've recorded, not a diagnosis.";

    private static readonly Dictionary<TriggerType, string> TriggerLabels = new()
    {
        [TriggerType.Stress] = "Stress",
        [TriggerType.Boredom] = "Boredom",
        [TriggerType.Payday] = "Payday",
        [TriggerType.TryingToRecoverLosses] = "Trying to win back losses",
        [TriggerType.Alcohol] = "Drinking",
        [TriggerType.FriendsGambling] = "Friends gambling",
        [TriggerType.Loneliness] = "Feeling lonely",
        [TriggerType.Excitement] = "Wanting excitement",
        [TriggerType.FinancialPressure] = "Money pressure",
        [TriggerType.Other] = "Something else",
    };

    private static readonly Dictionary<CopingStrategy, string> CopingLabels = new()
    {
        [CopingStrategy.Walked] = "Went for a walk or moved",
        [CopingStrategy.TalkedToSomeone] = "Talked to someone",
        [CopingStrategy.Breathing] = "Breathing or grounding",
        [CopingStrategy.Distraction] = "Did something else",
        [CopingStrategy.BlockedSites] = "Blocking kept me out",
        [CopingStrategy.LeftPhone] = "Put the phone away",
        [CopingStrategy.RememberedGoal] = "Thought about my goal",
        [CopingStrategy.Other] = "Something else",
    };

    public static IReadOnlyList<string> Describe(IReadOnlyList<UrgeEvent> events)
    {
        if (events.Count < MinimumEvents) return [];
        return new[] { TimeOfDay(events), DayOfWeek(events), Trigger(events), WhatHelped(events) }.OfType<string>().ToList();
    }

    private static string? TimeOfDay(IReadOnlyList<UrgeEvent> events)
    {
        var byHour = new int[24];
        foreach (var e in events) byHour[e.LocalTime.Hour]++;
        int bestStart = 0, bestCount = 0;
        for (var start = 0; start < 24; start++)
        {
            var count = byHour[start] + byHour[(start + 1) % 24] + byHour[(start + 2) % 24];
            if (count > bestCount) (bestStart, bestCount) = (start, count);
        }
        if (bestCount < 3 || (double)bestCount / events.Count < 0.4) return null;
        static string Hh(int h) => $"{h % 24:00}:00";
        var share = bestCount == events.Count ? "All" : $"{bestCount} of {events.Count}";
        return $"{share} of your recorded urges happened between {Hh(bestStart)} and {Hh(bestStart + 3)}.";
    }

    private static readonly string[] Days = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"];

    private static string? DayOfWeek(IReadOnlyList<UrgeEvent> events)
    {
        if (events.Count < 7) return null;
        var byDay = new int[7];
        // Monday first, as in the app.
        foreach (var e in events) byDay[((int)e.LocalTime.DayOfWeek + 6) % 7]++;
        var top = Array.IndexOf(byDay, byDay.Max());
        if ((double)byDay[top] / events.Count < 0.3) return null;
        return $"Urges came up most often on {Days[top]} ({byDay[top]} of {events.Count}).";
    }

    private static string? Trigger(IReadOnlyList<UrgeEvent> events)
    {
        var withTrigger = events.Count(e => e.Trigger is not null);
        var counts = events.Where(e => e.Trigger is { } t && t != TriggerType.Other)
            .GroupBy(e => e.Trigger!.Value).Select(g => (Trigger: g.Key, Count: g.Count())).ToList();
        if (counts.Count == 0 || withTrigger < 4) return null;
        var top = counts.OrderByDescending(c => c.Count).ThenBy(c => c.Trigger).First();
        if (top.Count < 2 || (double)top.Count / withTrigger < 0.3) return null;
        return $"\"{TriggerLabels[top.Trigger]}\" was the trigger you recorded most ({top.Count} of {withTrigger} times).";
    }

    private static string? WhatHelped(IReadOnlyList<UrgeEvent> events)
    {
        var counts = events.Where(e => e.Gambled == false)
            .SelectMany(e => e.Helped.Distinct()).Where(h => h != CopingStrategy.Other)
            .GroupBy(h => h).Select(g => (Strategy: g.Key, Count: g.Count())).ToList();
        if (counts.Count == 0) return null;
        var top = counts.OrderByDescending(c => c.Count).ThenBy(c => c.Strategy).First();
        if (top.Count < 2) return null;
        return $"\"{CopingLabels[top.Strategy]}\" was part of {top.Count} of the times you got through an urge.";
    }
}

public sealed class JournalHandlers(IUserProfileRepository profiles, IJournalRepository journal, IUnitOfWork unitOfWork, TimeProvider time)
{
    private DateTime Now => time.GetUtcNow().UtcDateTime;

    public async Task<PagedResponse<JournalEntryResponse>> ListAsync(Guid appUserId, int page, int pageSize, CancellationToken ct = default)
    {
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, Paging.MaxPageSize);
        var profileId = await profiles.RequireIdAsync(appUserId, ct);
        var (items, total) = await journal.GetPageAsync(profileId, page, pageSize, ct);
        return new(items.Select(JournalEntryResponse.From).ToList(), page, pageSize, total);
    }

    public async Task<JournalEntryResponse> CreateAsync(Guid appUserId, SaveJournalEntryRequest r, CancellationToken ct = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, ct);
        if (r.Id is { } id && await journal.ExistsAsync(id, ct)) throw new ConflictException("A journal entry with this id already exists.");
        var entry = JournalEntry.Create(r.Id, profileId, r.OccurredAtUtc!.Value.AsUtc(), r.Mood, r.Trigger, r.UrgeIntensity, r.Outcome, r.Helped ?? [], r.Note, Now);
        journal.Add(entry);
        await unitOfWork.SaveChangesAsync(ct);
        return JournalEntryResponse.From(entry);
    }

    public async Task<JournalEntryResponse> UpdateAsync(Guid appUserId, Guid id, SaveJournalEntryRequest r, CancellationToken ct = default)
    {
        var entry = await RequireAsync(appUserId, id, ct);
        entry.Update(r.OccurredAtUtc!.Value.AsUtc(), r.Mood, r.Trigger, r.UrgeIntensity, r.Outcome, r.Helped ?? [], r.Note, Now);
        await unitOfWork.SaveChangesAsync(ct);
        return JournalEntryResponse.From(entry);
    }

    public async Task DeleteAsync(Guid appUserId, Guid id, CancellationToken ct = default)
    {
        journal.Remove(await RequireAsync(appUserId, id, ct));
        await unitOfWork.SaveChangesAsync(ct);
    }

    /// <summary>Patterns across journal urges and "I feel like gambling" sessions, in the user's local time.</summary>
    public async Task<JournalInsightsResponse> InsightsAsync(Guid appUserId, string? timeZone, CancellationToken ct = default)
    {
        if (!StatsPeriods.TryFindZone(timeZone, out var zone))
            throw new ValidationException([new FluentValidation.Results.ValidationFailure("timeZone", "Unknown time zone.")]);
        var profileId = await profiles.RequireIdAsync(appUserId, ct);
        DateTime Local(DateTime utc) => TimeZoneInfo.ConvertTimeFromUtc(utc, zone);

        var events = (await journal.GetAllAsync(profileId, ct))
            .Where(j => j.HadUrge)
            .Select(j => new UrgeEvent(Local(j.OccurredAtUtc), j.Trigger, j.Outcome is null ? null : j.Outcome == JournalOutcome.Gambled, j.Helped))
            .Concat((await journal.GetCompletedUrgesAsync(profileId, ct))
                .Select(u => new UrgeEvent(Local(u.StartedAtUtc), u.Trigger, u.Outcome is null ? null : u.Outcome == UrgeOutcome.Gambled, [])))
            .ToList();
        return new(JournalInsights.Describe(events), events.Count, JournalInsights.MinimumEvents, JournalInsights.Disclaimer);
    }

    private async Task<JournalEntry> RequireAsync(Guid appUserId, Guid id, CancellationToken ct)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, ct);
        return await journal.GetAsync(id, profileId, ct) ?? throw new NotFoundException("Journal entry not found.");
    }
}
