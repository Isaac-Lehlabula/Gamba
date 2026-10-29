using FluentValidation;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Gambling;

namespace Reclaim.Application.GamblingEntries;

public sealed record SaveGamblingEntryRequest(
    Guid? Id,
    GamblingEntryType? EntryType,
    decimal? Amount,
    DateTime? OccurredAtUtc,
    GamblingType? GamblingType,
    string? PlatformName,
    string? Notes);

public sealed record GamblingEntryResponse(
    Guid Id,
    GamblingEntryType EntryType,
    decimal Amount,
    DateTime OccurredAtUtc,
    GamblingType GamblingType,
    string? PlatformName,
    string? Notes,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc)
{
    public static GamblingEntryResponse From(GamblingEntry e) =>
        new(e.Id, e.EntryType, e.Amount, e.OccurredAtUtc, e.GamblingType, e.Platform?.Name, e.Notes, e.CreatedAtUtc, e.UpdatedAtUtc);
}

/// <summary>Query-string filters for listing entries.</summary>
public sealed class GamblingEntryQuery
{
    public DateTime? From { get; init; }
    public DateTime? To { get; init; }
    public GamblingEntryType? EntryType { get; init; }
    public GamblingType? GamblingType { get; init; }
    public string? Platform { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = Paging.DefaultPageSize;
}

public sealed record GamblingTotals(decimal Deposited, decimal Withdrawn, decimal Won, decimal Lost, decimal NetLoss)
{
    /// <summary>
    /// Net loss counts both styles of logging: money moved (deposits minus withdrawals) and
    /// outcomes (losses minus wins). Most people log one style; mixing both for the same money
    /// would count it twice, which the app explains when entries are added. Negative means ahead.
    /// </summary>
    public static GamblingTotals From(IReadOnlyDictionary<GamblingEntryType, decimal> sums)
    {
        decimal Get(GamblingEntryType t) => sums.TryGetValue(t, out var v) ? v : 0m;
        var deposited = Get(GamblingEntryType.Deposit);
        var withdrawn = Get(GamblingEntryType.Withdrawal);
        var won = Get(GamblingEntryType.Win);
        var lost = Get(GamblingEntryType.Loss);
        return new(deposited, withdrawn, won, lost, deposited - withdrawn + lost - won);
    }
}

public sealed record GamblingStatsResponse(
    string TimeZone,
    GamblingTotals Today,
    GamblingTotals ThisWeek,
    GamblingTotals ThisMonth,
    GamblingTotals Lifetime);

/// <summary>Start of today, this week (Monday) and this month in the user's time zone, as UTC.</summary>
public static class StatsPeriods
{
    public const string DefaultTimeZone = "Africa/Johannesburg";

    public static (DateTime TodayUtc, DateTime WeekUtc, DateTime MonthUtc) Starts(DateTime nowUtc, TimeZoneInfo zone)
    {
        var local = TimeZoneInfo.ConvertTimeFromUtc(nowUtc, zone);
        var today = local.Date;
        var week = today.AddDays(-(((int)today.DayOfWeek + 6) % 7));
        var month = new DateTime(today.Year, today.Month, 1);
        return (ToUtc(today, zone), ToUtc(week, zone), ToUtc(month, zone));
    }

    private static DateTime ToUtc(DateTime localMidnight, TimeZoneInfo zone)
    {
        var unspecified = DateTime.SpecifyKind(localMidnight, DateTimeKind.Unspecified);
        // A DST jump can skip midnight; the period then starts at the first valid local time.
        while (zone.IsInvalidTime(unspecified))
            unspecified = unspecified.AddMinutes(30);
        return TimeZoneInfo.ConvertTimeToUtc(unspecified, zone);
    }

    public static bool TryFindZone(string? id, out TimeZoneInfo zone)
    {
        try
        {
            zone = TimeZoneInfo.FindSystemTimeZoneById(string.IsNullOrWhiteSpace(id) ? DefaultTimeZone : id);
            return true;
        }
        catch (Exception ex) when (ex is TimeZoneNotFoundException or InvalidTimeZoneException)
        {
            zone = TimeZoneInfo.Utc;
            return false;
        }
    }
}

public sealed class SaveGamblingEntryRequestValidator : AbstractValidator<SaveGamblingEntryRequest>
{
    public SaveGamblingEntryRequestValidator(TimeProvider time)
    {
        RuleFor(x => x.EntryType).NotNull().IsInEnum();
        RuleFor(x => x.Amount).NotNull().GreaterThan(0).LessThanOrEqualTo(GamblingEntry.MaxAmount).PrecisionScale(14, 2, true);
        RuleFor(x => x.OccurredAtUtc).NotNull()
            .Must(d => d!.Value.AsUtc() <= time.GetUtcNow().UtcDateTime + GamblingEntry.FutureTolerance)
            .WithMessage("An entry cannot be dated in the future.")
            .When(x => x.OccurredAtUtc is not null);
        RuleFor(x => x.GamblingType).NotNull().IsInEnum();
        RuleFor(x => x.PlatformName).MaximumLength(GamblingPlatform.MaxNameLength);
        RuleFor(x => x.Notes).MaximumLength(GamblingEntry.MaxNotesLength);
    }
}

public sealed class GamblingEntryQueryValidator : AbstractValidator<GamblingEntryQuery>
{
    public GamblingEntryQueryValidator()
    {
        RuleFor(x => x.EntryType).IsInEnum();
        RuleFor(x => x.GamblingType).IsInEnum();
        RuleFor(x => x.Platform).MaximumLength(GamblingPlatform.MaxNameLength);
        RuleFor(x => x.Page).GreaterThanOrEqualTo(1);
        RuleFor(x => x.PageSize).InclusiveBetween(1, Paging.MaxPageSize);
        RuleFor(x => x.To).GreaterThanOrEqualTo(x => x.From).When(x => x.From is not null && x.To is not null);
    }
}

/// <summary>Finds the profile's platform with this name, or creates it.</summary>
public sealed class PlatformResolver(IGamblingPlatformRepository platforms, TimeProvider time)
{
    public async Task<GamblingPlatform?> ResolveAsync(Guid profileId, string? name, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(name))
            return null;
        var existing = await platforms.FindAsync(profileId, GamblingPlatform.Normalize(name), cancellationToken);
        if (existing is not null)
            return existing;

        var created = GamblingPlatform.CreateForProfile(profileId, name, time.GetUtcNow().UtcDateTime);
        platforms.Add(created);
        return created;
    }
}

public sealed class CreateGamblingEntryHandler(
    IUserProfileRepository profiles,
    IGamblingEntryRepository entries,
    PlatformResolver platformResolver,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    public async Task<GamblingEntryResponse> HandleAsync(Guid appUserId, SaveGamblingEntryRequest request, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        if (request.Id is { } id && await entries.ExistsAsync(id, cancellationToken))
            throw new ConflictException("An entry with this id already exists.");

        var platform = await platformResolver.ResolveAsync(profileId, request.PlatformName, cancellationToken);
        var entry = GamblingEntry.Create(
            request.Id,
            profileId,
            request.EntryType!.Value,
            request.Amount!.Value,
            request.OccurredAtUtc!.Value.AsUtc(),
            request.GamblingType!.Value,
            platform,
            request.Notes,
            time.GetUtcNow().UtcDateTime);
        entries.Add(entry);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return GamblingEntryResponse.From(entry);
    }
}

public sealed class UpdateGamblingEntryHandler(
    IUserProfileRepository profiles,
    IGamblingEntryRepository entries,
    PlatformResolver platformResolver,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    public async Task<GamblingEntryResponse> HandleAsync(Guid appUserId, Guid entryId, SaveGamblingEntryRequest request, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        var entry = await entries.GetAsync(entryId, profileId, cancellationToken)
            ?? throw new NotFoundException("Entry not found.");

        var platform = await platformResolver.ResolveAsync(profileId, request.PlatformName, cancellationToken);
        entry.Update(
            request.EntryType!.Value,
            request.Amount!.Value,
            request.OccurredAtUtc!.Value.AsUtc(),
            request.GamblingType!.Value,
            platform,
            request.Notes,
            time.GetUtcNow().UtcDateTime);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return GamblingEntryResponse.From(entry);
    }
}

public sealed class DeleteGamblingEntryHandler(IUserProfileRepository profiles, IGamblingEntryRepository entries, IUnitOfWork unitOfWork)
{
    public async Task HandleAsync(Guid appUserId, Guid entryId, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        var entry = await entries.GetAsync(entryId, profileId, cancellationToken)
            ?? throw new NotFoundException("Entry not found.");
        entries.Remove(entry);
        await unitOfWork.SaveChangesAsync(cancellationToken);
    }
}

public sealed class ListGamblingEntriesHandler(
    IUserProfileRepository profiles,
    IGamblingEntryRepository entries,
    IGamblingPlatformRepository platforms)
{
    public async Task<PagedResponse<GamblingEntryResponse>> HandleAsync(Guid appUserId, GamblingEntryQuery query, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);

        Guid? platformId = null;
        if (!string.IsNullOrWhiteSpace(query.Platform))
        {
            var platform = await platforms.FindAsync(profileId, GamblingPlatform.Normalize(query.Platform), cancellationToken);
            if (platform is null)
                return new([], query.Page, query.PageSize, 0);
            platformId = platform.Id;
        }

        var filter = new GamblingEntryFilter(query.From?.AsUtc(), query.To?.AsUtc(), query.EntryType, query.GamblingType, platformId, query.Page, query.PageSize);
        var (items, total) = await entries.QueryAsync(profileId, filter, cancellationToken);
        return new(items.Select(GamblingEntryResponse.From).ToList(), query.Page, query.PageSize, total);
    }
}

public sealed class GetGamblingStatsHandler(IUserProfileRepository profiles, IGamblingEntryRepository entries, TimeProvider time)
{
    public async Task<GamblingStatsResponse> HandleAsync(Guid appUserId, string? timeZone, CancellationToken cancellationToken = default)
    {
        if (!StatsPeriods.TryFindZone(timeZone, out var zone))
            throw new FluentValidation.ValidationException([new FluentValidation.Results.ValidationFailure("timeZone", "Unknown time zone.")]);

        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        var (today, week, month) = StatsPeriods.Starts(time.GetUtcNow().UtcDateTime, zone);

        return new GamblingStatsResponse(
            zone.Id,
            GamblingTotals.From(await entries.SumByTypeAsync(profileId, today, cancellationToken)),
            GamblingTotals.From(await entries.SumByTypeAsync(profileId, week, cancellationToken)),
            GamblingTotals.From(await entries.SumByTypeAsync(profileId, month, cancellationToken)),
            GamblingTotals.From(await entries.SumByTypeAsync(profileId, null, cancellationToken)));
    }
}
