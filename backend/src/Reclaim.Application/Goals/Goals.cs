using FluentValidation;
using Reclaim.Application.Common;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Goals;

namespace Reclaim.Application.Goals;

public sealed record SaveGoalRequest(Guid? Id, string? Name, GoalCategory? Category, decimal? TargetAmount, DateTime? TargetDateUtc);

public sealed record AddContributionRequest(Guid? Id, decimal? Amount, ContributionSource? Source, DateTime? OccurredAtUtc);

public sealed record ContributionResponse(Guid Id, decimal Amount, ContributionSource Source, DateTime OccurredAtUtc);

public sealed record GoalResponse(
    Guid Id,
    string Name,
    GoalCategory Category,
    decimal TargetAmount,
    DateTime? TargetDateUtc,
    decimal SavedAmount,
    IReadOnlyList<ContributionResponse> Contributions)
{
    public static GoalResponse From(RecoveryGoal g) => new(
        g.Id, g.Name, g.Category, g.TargetAmount, g.TargetDateUtc, g.SavedAmount,
        g.Contributions.OrderByDescending(c => c.OccurredAtUtc)
            .Select(c => new ContributionResponse(c.Id, c.Amount, c.Source, c.OccurredAtUtc)).ToList());
}

public sealed class SaveGoalRequestValidator : AbstractValidator<SaveGoalRequest>
{
    public SaveGoalRequestValidator()
    {
        RuleFor(x => x.Name).NotEmpty().MaximumLength(RecoveryGoal.MaxNameLength);
        RuleFor(x => x.Category).NotNull().IsInEnum();
        RuleFor(x => x.TargetAmount).NotNull().GreaterThan(0).LessThanOrEqualTo(RecoveryGoal.MaxAmount).PrecisionScale(14, 2, true);
    }
}

public sealed class AddContributionRequestValidator : AbstractValidator<AddContributionRequest>
{
    public AddContributionRequestValidator()
    {
        RuleFor(x => x.Amount).NotNull().GreaterThan(0).LessThanOrEqualTo(RecoveryGoal.MaxAmount).PrecisionScale(14, 2, true);
        RuleFor(x => x.Source).NotNull().IsInEnum();
    }
}

public sealed class GoalHandlers(IUserProfileRepository profiles, IGoalRepository goals, IUnitOfWork unitOfWork, TimeProvider time)
{
    private DateTime Now => time.GetUtcNow().UtcDateTime;

    public async Task<IReadOnlyList<GoalResponse>> ListAsync(Guid appUserId, CancellationToken ct = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, ct);
        return (await goals.ListAsync(profileId, ct)).Select(GoalResponse.From).ToList();
    }

    public async Task<GoalResponse> CreateAsync(Guid appUserId, SaveGoalRequest request, CancellationToken ct = default)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, ct);
        if (request.Id is { } id && await goals.ExistsAsync(id, ct))
            throw new ConflictException("A goal with this id already exists.");
        var goal = RecoveryGoal.Create(request.Id, profileId, request.Name!, request.Category!.Value, request.TargetAmount!.Value,
            request.TargetDateUtc?.AsUtc(), Now);
        goals.Add(goal);
        await unitOfWork.SaveChangesAsync(ct);
        return GoalResponse.From(goal);
    }

    public async Task<GoalResponse> UpdateAsync(Guid appUserId, Guid goalId, SaveGoalRequest request, CancellationToken ct = default)
    {
        var goal = await RequireGoalAsync(appUserId, goalId, ct);
        goal.Update(request.Name!, request.Category!.Value, request.TargetAmount!.Value, request.TargetDateUtc?.AsUtc(), Now);
        await unitOfWork.SaveChangesAsync(ct);
        return GoalResponse.From(goal);
    }

    public async Task DeleteAsync(Guid appUserId, Guid goalId, CancellationToken ct = default)
    {
        goals.Remove(await RequireGoalAsync(appUserId, goalId, ct));
        await unitOfWork.SaveChangesAsync(ct);
    }

    public async Task<GoalResponse> AddContributionAsync(Guid appUserId, Guid goalId, AddContributionRequest request, CancellationToken ct = default)
    {
        var goal = await RequireGoalAsync(appUserId, goalId, ct);
        if (request.Id is { } id && await goals.ContributionExistsAsync(id, ct))
            throw new ConflictException("A contribution with this id already exists.");
        goal.AddContribution(request.Id, request.Amount!.Value, request.Source!.Value, request.OccurredAtUtc?.AsUtc() ?? Now, Now);
        await unitOfWork.SaveChangesAsync(ct);
        return GoalResponse.From(goal);
    }

    public async Task<GoalResponse> RemoveContributionAsync(Guid appUserId, Guid goalId, Guid contributionId, CancellationToken ct = default)
    {
        var goal = await RequireGoalAsync(appUserId, goalId, ct);
        if (goal.Contributions.All(c => c.Id != contributionId)) throw new NotFoundException("Contribution not found.");
        goal.RemoveContribution(contributionId, Now);
        await unitOfWork.SaveChangesAsync(ct);
        return GoalResponse.From(goal);
    }

    private async Task<RecoveryGoal> RequireGoalAsync(Guid appUserId, Guid goalId, CancellationToken ct)
    {
        var profileId = await profiles.RequireIdAsync(appUserId, ct);
        return await goals.GetAsync(goalId, profileId, ct) ?? throw new NotFoundException("Goal not found.");
    }
}
