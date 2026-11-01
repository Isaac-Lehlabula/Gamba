using FluentValidation;
using Reclaim.Application.Assessment;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Application.GamblingEntries;
using Reclaim.Application.Goals;
using Reclaim.Application.Journal;
using Reclaim.Application.Onboarding;
using Reclaim.Application.Urges;
using Reclaim.Domain.Assessment;
using Reclaim.Domain.Gambling;
using Reclaim.Domain.Goals;
using Reclaim.Domain.Journal;
using Reclaim.Domain.Onboarding;
using Reclaim.Domain.Urges;
using Reclaim.Domain.Users;

namespace Reclaim.Application.Backup;

public sealed record BackupProfile(string? DisplayName, RecoveryGoalType? RecoveryGoalType, DateTime? QuitOrReductionStartDateUtc);

public sealed record BackupAssessment(Guid Id, Dictionary<string, int> Answers, DateTime CreatedAtUtc);

public sealed record BackupUrge(
    Guid Id,
    TriggerType Trigger,
    int? Intensity,
    int CoolingOffMinutes,
    DateTime StartedAtUtc,
    UrgeOutcome? Outcome,
    DateTime? ResolvedAtUtc,
    string? Notes);

public sealed record BackupContribution(Guid Id, decimal Amount, ContributionSource Source, DateTime OccurredAtUtc);

public sealed record BackupGoal(
    Guid Id,
    string Name,
    GoalCategory Category,
    decimal TargetAmount,
    DateTime? TargetDateUtc,
    List<BackupContribution> Contributions);

/// <summary>Everything stored on the phone, pushed in one go by "Back up my data".</summary>
public sealed record BackupRequest(
    BackupProfile? Profile,
    List<SubmitOnboardingRequest>? OnboardingResponses,
    List<BackupAssessment>? Assessments,
    List<SaveGamblingEntryRequest>? Entries,
    List<BackupUrge>? Urges,
    List<BackupGoal>? Goals,
    List<SaveJournalEntryRequest>? JournalEntries = null);

/// <param name="Skipped">Records whose id already belongs to another account; never overwritten.</param>
public sealed record BackupResponse(int Created, int Updated, int Skipped);

public sealed class BackupRequestValidator : AbstractValidator<BackupRequest>
{
    public const int MaxItemsPerKind = 10_000;

    public BackupRequestValidator(TimeProvider time)
    {
        RuleFor(x => x.OnboardingResponses).Must(l => l is null || l.Count <= MaxItemsPerKind);
        RuleFor(x => x.Assessments).Must(l => l is null || l.Count <= MaxItemsPerKind);
        RuleFor(x => x.Entries).Must(l => l is null || l.Count <= MaxItemsPerKind);
        RuleFor(x => x.Urges).Must(l => l is null || l.Count <= MaxItemsPerKind);
        RuleFor(x => x.Goals).Must(l => l is null || l.Count <= MaxItemsPerKind);
        RuleFor(x => x.JournalEntries).Must(l => l is null || l.Count <= MaxItemsPerKind);
        RuleForEach(x => x.JournalEntries).SetValidator(new SaveJournalEntryRequestValidator())
            .Must(j => j.Id is not null).WithMessage("Backed-up records need their id.");
        RuleForEach(x => x.OnboardingResponses).SetValidator(new SubmitOnboardingRequestValidator())
            .Must(r => r.Id is not null).WithMessage("Backed-up records need their id.");
        RuleForEach(x => x.Entries).SetValidator(new SaveGamblingEntryRequestValidator(time))
            .Must(e => e.Id is not null).WithMessage("Backed-up records need their id.");
    }
}

/// <summary>
/// Creates what the server doesn't have and updates what it does, matching on the
/// client-generated ids. Safe to run repeatedly. It does not delete anything: removing data
/// from a backup is done through the normal endpoints or account deletion.
/// </summary>
public sealed class BackupHandler(
    IUserProfileRepository profiles,
    IOnboardingResponseRepository onboarding,
    ISelfAssessmentRepository assessments,
    IGamblingEntryRepository entries,
    PlatformResolver platformResolver,
    IUrgeRepository urges,
    IGoalRepository goals,
    IJournalRepository journal,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    public async Task<BackupResponse> HandleAsync(Guid appUserId, BackupRequest request, CancellationToken ct = default)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var profile = await profiles.GetByAppUserIdAsync(appUserId, ct) ?? throw new NotFoundException("Profile not found.");
        int created = 0, updated = 0, skipped = 0;

        if (request.Profile is { } p)
        {
            profile.Update(p.DisplayName, p.RecoveryGoalType, p.QuitOrReductionStartDateUtc?.AsUtc(), now);
            updated++;
        }

        foreach (var r in request.OnboardingResponses ?? [])
        {
            if (await onboarding.ExistsAsync(r.Id!.Value, ct)) { skipped++; continue; }
            onboarding.Add(OnboardingResponse.Create(r.Id, profile.Id, r.GamblingTypes!, r.FrequencyBand!.Value, r.ApproxMonthlySpend,
                r.Triggers!, r.Goal!.Value, r.MoneyGoalPreference, now));
            created++;
        }

        foreach (var a in request.Assessments ?? [])
        {
            if (await assessments.ExistsAsync(a.Id, ct)) { skipped++; continue; }
            assessments.Add(SelfAssessmentResult.Submit(a.Id, profile.Id, a.Answers, now));
            created++;
        }

        foreach (var e in request.Entries ?? [])
        {
            var platform = await platformResolver.ResolveAsync(profile.Id, e.PlatformName, ct);
            if (await entries.GetAsync(e.Id!.Value, profile.Id, ct) is { } existing)
            {
                existing.Update(e.EntryType!.Value, e.Amount!.Value, e.OccurredAtUtc!.Value.AsUtc(), e.GamblingType!.Value, platform, e.Notes, now);
                updated++;
            }
            else if (await entries.ExistsAsync(e.Id.Value, ct)) skipped++;
            else
            {
                entries.Add(GamblingEntry.Create(e.Id, profile.Id, e.EntryType!.Value, e.Amount!.Value, e.OccurredAtUtc!.Value.AsUtc(),
                    e.GamblingType!.Value, platform, e.Notes, now));
                created++;
            }
        }

        foreach (var u in request.Urges ?? [])
        {
            var existing = await urges.GetAsync(u.Id, profile.Id, ct);
            if (existing is null && await urges.ExistsAsync(u.Id, ct)) { skipped++; continue; }
            var urge = existing ?? Urge.Start(u.Id, profile.Id, u.Trigger, u.Intensity, InitialPause(u.CoolingOffMinutes), u.StartedAtUtc.AsUtc(), now);
            while (urge.CoolingOffMinutes < u.CoolingOffMinutes && !urge.IsResolved) urge.Extend(now);
            if (u.Outcome is { } outcome && !urge.IsResolved) urge.Resolve(outcome, u.Notes, (u.ResolvedAtUtc ?? now).AsUtc(), now);
            if (existing is null) { urges.Add(urge); created++; } else updated++;
        }

        foreach (var g in request.Goals ?? [])
        {
            var existing = await goals.GetAsync(g.Id, profile.Id, ct);
            if (existing is null && await goals.ExistsAsync(g.Id, ct)) { skipped++; continue; }
            var goal = existing ?? RecoveryGoal.Create(g.Id, profile.Id, g.Name, g.Category, g.TargetAmount, g.TargetDateUtc?.AsUtc(), now);
            if (existing is not null) goal.Update(g.Name, g.Category, g.TargetAmount, g.TargetDateUtc?.AsUtc(), now);

            // The phone is the source of truth for a goal's contributions in a backup.
            var wanted = g.Contributions.Select(c => c.Id).ToHashSet();
            foreach (var stale in goal.Contributions.Where(c => !wanted.Contains(c.Id)).Select(c => c.Id).ToList())
                goal.RemoveContribution(stale, now);
            foreach (var c in g.Contributions.Where(c => goal.Contributions.All(x => x.Id != c.Id)))
            {
                if (await goals.ContributionExistsAsync(c.Id, ct)) { skipped++; continue; }
                goal.AddContribution(c.Id, c.Amount, c.Source, c.OccurredAtUtc.AsUtc(), now);
            }
            if (existing is null) { goals.Add(goal); created++; } else updated++;
        }

        foreach (var j in request.JournalEntries ?? [])
        {
            if (await journal.GetAsync(j.Id!.Value, profile.Id, ct) is { } existing)
            {
                existing.Update(j.OccurredAtUtc!.Value.AsUtc(), j.Mood, j.Trigger, j.UrgeIntensity, j.Outcome, j.Helped ?? [], j.Note, now);
                updated++;
            }
            else if (await journal.ExistsAsync(j.Id.Value, ct)) skipped++;
            else
            {
                journal.Add(JournalEntry.Create(j.Id, profile.Id, j.OccurredAtUtc!.Value.AsUtc(), j.Mood, j.Trigger, j.UrgeIntensity,
                    j.Outcome, j.Helped ?? [], j.Note, now));
                created++;
            }
        }

        await unitOfWork.SaveChangesAsync(ct);
        return new(created, updated, skipped);
    }

    /// <summary>An extended pause is recreated from the largest standard length at or below it, then extended.</summary>
    private static int InitialPause(int minutes) =>
        Urge.PauseOptions.Where(o => o <= minutes).DefaultIfEmpty(Urge.PauseOptions.Min()).Max();
}
