using FluentValidation;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Gambling;
using Reclaim.Domain.Onboarding;
using Reclaim.Domain.Users;

namespace Reclaim.Application.Onboarding;

// Required enums are nullable here so a missing field fails validation instead of silently
// becoming the enum's first value.
public sealed record SubmitOnboardingRequest(
    Guid? Id,
    List<GamblingType>? GamblingTypes,
    FrequencyBand? FrequencyBand,
    decimal? ApproxMonthlySpend,
    List<TriggerType>? Triggers,
    RecoveryGoalType? Goal,
    string? MoneyGoalPreference);

public sealed record OnboardingResponseDto(
    Guid Id,
    IReadOnlyList<GamblingType> GamblingTypes,
    FrequencyBand FrequencyBand,
    decimal? ApproxMonthlySpend,
    IReadOnlyList<TriggerType> Triggers,
    RecoveryGoalType Goal,
    string? MoneyGoalPreference,
    DateTime CreatedAtUtc)
{
    public static OnboardingResponseDto From(OnboardingResponse r) =>
        new(r.Id, r.GamblingTypes, r.FrequencyBand, r.ApproxMonthlySpend, r.Triggers, r.Goal, r.MoneyGoalPreference, r.CreatedAtUtc);
}

public sealed class SubmitOnboardingRequestValidator : AbstractValidator<SubmitOnboardingRequest>
{
    public SubmitOnboardingRequestValidator()
    {
        RuleFor(x => x.GamblingTypes).NotNull();
        RuleForEach(x => x.GamblingTypes).IsInEnum();
        RuleFor(x => x.FrequencyBand).NotNull().IsInEnum();
        RuleFor(x => x.ApproxMonthlySpend).InclusiveBetween(0, OnboardingResponse.MaxMonthlySpend);
        RuleFor(x => x.Triggers).NotNull();
        RuleForEach(x => x.Triggers).IsInEnum();
        RuleFor(x => x.Goal).NotNull().IsInEnum();
        RuleFor(x => x.MoneyGoalPreference).MaximumLength(OnboardingResponse.MaxMoneyGoalPreferenceLength);
    }
}

public sealed class SubmitOnboardingHandler(
    IUserProfileRepository profiles,
    IOnboardingResponseRepository responses,
    IUnitOfWork unitOfWork,
    TimeProvider time)
{
    public async Task<OnboardingResponseDto> HandleAsync(Guid appUserId, SubmitOnboardingRequest request, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        if (request.Id is { } id && await responses.ExistsAsync(id, cancellationToken))
            throw new ConflictException("An onboarding response with this id already exists.");

        var response = OnboardingResponse.Create(
            request.Id,
            profileId,
            request.GamblingTypes!,
            request.FrequencyBand!.Value,
            request.ApproxMonthlySpend,
            request.Triggers!,
            request.Goal!.Value,
            request.MoneyGoalPreference,
            time.GetUtcNow().UtcDateTime);
        responses.Add(response);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return OnboardingResponseDto.From(response);
    }
}

public sealed class GetLatestOnboardingHandler(IUserProfileRepository profiles, IOnboardingResponseRepository responses)
{
    public async Task<OnboardingResponseDto> HandleAsync(Guid appUserId, CancellationToken cancellationToken = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, cancellationToken);
        var latest = await responses.GetLatestAsync(profileId, cancellationToken)
            ?? throw new NotFoundException("No onboarding answers have been submitted yet.");
        return OnboardingResponseDto.From(latest);
    }
}
