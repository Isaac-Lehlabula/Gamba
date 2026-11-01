using FluentValidation;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Onboarding;
using Reclaim.Domain.Urges;

namespace Reclaim.Application.Urges;

public sealed record StartUrgeRequest(Guid? Id, TriggerType? Trigger, int? Intensity, int? CoolingOffMinutes, DateTime? StartedAtUtc);

public sealed record ResolveUrgeRequest(UrgeOutcome? Outcome, string? Notes, DateTime? ResolvedAtUtc);

public sealed record UrgeResponse(
    Guid Id,
    TriggerType Trigger,
    int? Intensity,
    int CoolingOffMinutes,
    DateTime StartedAtUtc,
    DateTime? ResolvedAtUtc,
    UrgeOutcome? Outcome,
    string? Notes)
{
    public static UrgeResponse From(Urge u) =>
        new(u.Id, u.Trigger, u.Intensity, u.CoolingOffMinutes, u.StartedAtUtc, u.ResolvedAtUtc, u.Outcome, u.Notes);
}

public sealed class StartUrgeRequestValidator : AbstractValidator<StartUrgeRequest>
{
    public StartUrgeRequestValidator()
    {
        RuleFor(x => x.Trigger).NotNull().IsInEnum();
        RuleFor(x => x.Intensity).InclusiveBetween(1, 5);
        RuleFor(x => x.CoolingOffMinutes).NotNull()
            .Must(m => m is null || Urge.PauseOptions.Contains(m.Value)).WithMessage("Pause must be 10, 20, 30 or 60 minutes.");
    }
}

public sealed class ResolveUrgeRequestValidator : AbstractValidator<ResolveUrgeRequest>
{
    public ResolveUrgeRequestValidator()
    {
        RuleFor(x => x.Outcome).NotNull().IsInEnum();
        RuleFor(x => x.Notes).MaximumLength(Urge.MaxNotesLength);
    }
}

public sealed class StartUrgeHandler(IUserProfileRepository profiles, IUrgeRepository urges, IUnitOfWork unitOfWork, TimeProvider time)
{
    public async Task<UrgeResponse> HandleAsync(Guid appUserId, StartUrgeRequest request, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        if (request.Id is { } id && await urges.ExistsAsync(id, cancellationToken))
            throw new ConflictException("An urge with this id already exists.");

        var now = time.GetUtcNow().UtcDateTime;
        var urge = Urge.Start(request.Id, profileId, request.Trigger!.Value, request.Intensity, request.CoolingOffMinutes!.Value,
            request.StartedAtUtc?.AsUtc() ?? now, now);
        urges.Add(urge);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return UrgeResponse.From(urge);
    }
}

public sealed class ExtendUrgeHandler(IUserProfileRepository profiles, IUrgeRepository urges, IUnitOfWork unitOfWork, TimeProvider time)
{
    public async Task<UrgeResponse> HandleAsync(Guid appUserId, Guid urgeId, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        var urge = await urges.GetAsync(urgeId, profileId, cancellationToken) ?? throw new NotFoundException("Urge not found.");
        urge.Extend(time.GetUtcNow().UtcDateTime);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return UrgeResponse.From(urge);
    }
}

public sealed class ResolveUrgeHandler(IUserProfileRepository profiles, IUrgeRepository urges, IUnitOfWork unitOfWork, TimeProvider time)
{
    public async Task<UrgeResponse> HandleAsync(Guid appUserId, Guid urgeId, ResolveUrgeRequest request, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        var urge = await urges.GetAsync(urgeId, profileId, cancellationToken) ?? throw new NotFoundException("Urge not found.");
        var now = time.GetUtcNow().UtcDateTime;
        urge.Resolve(request.Outcome!.Value, request.Notes, request.ResolvedAtUtc?.AsUtc() ?? now, now);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return UrgeResponse.From(urge);
    }
}

public sealed class ListUrgesHandler(IUserProfileRepository profiles, IUrgeRepository urges)
{
    public async Task<PagedResponse<UrgeResponse>> HandleAsync(Guid appUserId, int page, int pageSize, CancellationToken cancellationToken = default)
    {
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, Paging.MaxPageSize);
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        var (items, total) = await urges.GetPageAsync(profileId, page, pageSize, cancellationToken);
        return new(items.Select(UrgeResponse.From).ToList(), page, pageSize, total);
    }
}
