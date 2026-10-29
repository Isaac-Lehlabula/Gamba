using FluentValidation;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Users;

namespace Reclaim.Application.Profile;

public sealed record ProfileResponse(
    Guid Id,
    Guid LocalProfileId,
    string? DisplayName,
    RecoveryGoalType? RecoveryGoalType,
    DateTime? QuitOrReductionStartDateUtc,
    DateTime UpdatedAtUtc)
{
    public static ProfileResponse From(UserProfile p) =>
        new(p.Id, p.LocalProfileId, p.DisplayName, p.RecoveryGoalType, p.QuitOrReductionStartDateUtc, p.UpdatedAtUtc);
}

public sealed record UpdateProfileRequest(
    string? DisplayName,
    RecoveryGoalType? RecoveryGoalType,
    DateTime? QuitOrReductionStartDateUtc);

public sealed class UpdateProfileRequestValidator : AbstractValidator<UpdateProfileRequest>
{
    public UpdateProfileRequestValidator(TimeProvider time)
    {
        RuleFor(x => x.DisplayName).MaximumLength(UserProfile.MaxDisplayNameLength);
        RuleFor(x => x.RecoveryGoalType).IsInEnum();
        RuleFor(x => x.QuitOrReductionStartDateUtc)
            .Must(d => d is null || d.Value.AsUtc() <= time.GetUtcNow().UtcDateTime)
            .WithMessage("Start date cannot be in the future.");
    }
}

public sealed class GetProfileHandler(IUserProfileRepository profiles)
{
    public async Task<ProfileResponse> HandleAsync(Guid appUserId, CancellationToken cancellationToken = default)
    {
        var profile = await profiles.GetByAppUserIdAsync(appUserId, cancellationToken)
            ?? throw new NotFoundException("Profile not found.");
        return ProfileResponse.From(profile);
    }
}

public sealed class UpdateProfileHandler(IUserProfileRepository profiles, IUnitOfWork unitOfWork, TimeProvider time)
{
    public async Task<ProfileResponse> HandleAsync(Guid appUserId, UpdateProfileRequest request, CancellationToken cancellationToken = default)
    {
        var profile = await profiles.GetByAppUserIdAsync(appUserId, cancellationToken)
            ?? throw new NotFoundException("Profile not found.");

        profile.Update(
            request.DisplayName,
            request.RecoveryGoalType,
            request.QuitOrReductionStartDateUtc?.AsUtc(),
            time.GetUtcNow().UtcDateTime);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return ProfileResponse.From(profile);
    }
}
