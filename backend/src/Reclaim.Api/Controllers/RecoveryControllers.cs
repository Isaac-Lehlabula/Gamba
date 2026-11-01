using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Reclaim.Api.Infrastructure;
using Reclaim.Application.Backup;
using Reclaim.Application.Common;
using Reclaim.Application.Content;
using Reclaim.Application.Dashboard;
using Reclaim.Application.Goals;
using Reclaim.Application.Urges;

namespace Reclaim.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/urges")]
public sealed class UrgesController : ControllerBase
{
    [HttpPost]
    public async Task<ActionResult<UrgeResponse>> Start(StartUrgeRequest request, [FromServices] StartUrgeHandler handler, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await handler.HandleAsync(User.GetUserId(), request, ct));

    [HttpPut("{id:guid}/extend")]
    public async Task<ActionResult<UrgeResponse>> Extend(Guid id, [FromServices] ExtendUrgeHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(User.GetUserId(), id, ct);

    [HttpPut("{id:guid}/resolve")]
    public async Task<ActionResult<UrgeResponse>> Resolve(Guid id, ResolveUrgeRequest request, [FromServices] ResolveUrgeHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(User.GetUserId(), id, request, ct);

    [HttpGet]
    public async Task<ActionResult<PagedResponse<UrgeResponse>>> List(
        [FromServices] ListUrgesHandler handler, CancellationToken ct, [FromQuery] int page = 1, [FromQuery] int pageSize = Paging.DefaultPageSize) =>
        await handler.HandleAsync(User.GetUserId(), page, pageSize, ct);
}

[ApiController]
[Authorize]
[Route("api/v1/goals")]
public sealed class GoalsController(GoalHandlers goals) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<GoalResponse>>> List(CancellationToken ct) => Ok(await goals.ListAsync(User.GetUserId(), ct));

    [HttpPost]
    public async Task<ActionResult<GoalResponse>> Create(SaveGoalRequest request, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await goals.CreateAsync(User.GetUserId(), request, ct));

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<GoalResponse>> Update(Guid id, SaveGoalRequest request, CancellationToken ct) =>
        await goals.UpdateAsync(User.GetUserId(), id, request, ct);

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        await goals.DeleteAsync(User.GetUserId(), id, ct);
        return NoContent();
    }

    [HttpPost("{id:guid}/contributions")]
    public async Task<ActionResult<GoalResponse>> AddContribution(Guid id, AddContributionRequest request, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await goals.AddContributionAsync(User.GetUserId(), id, request, ct));

    [HttpDelete("{id:guid}/contributions/{contributionId:guid}")]
    public async Task<ActionResult<GoalResponse>> RemoveContribution(Guid id, Guid contributionId, CancellationToken ct) =>
        await goals.RemoveContributionAsync(User.GetUserId(), id, contributionId, ct);
}

[ApiController]
[Authorize]
[Route("api/v1/dashboard")]
public sealed class DashboardController : ControllerBase
{
    [HttpGet("summary")]
    public async Task<ActionResult<DashboardSummaryResponse>> Summary(
        [FromServices] GetDashboardSummaryHandler handler, CancellationToken ct, [FromQuery] string? timeZone = null) =>
        await handler.HandleAsync(User.GetUserId(), timeZone, ct);
}

[ApiController]
[Authorize]
[Route("api/v1/backup")]
public sealed class BackupController : ControllerBase
{
    [HttpPost]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult<BackupResponse>> Backup(BackupRequest request, [FromServices] BackupHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(User.GetUserId(), request, ct);
}

/// <summary>Public content: no account needed, so the anonymous app can use it too.</summary>
[ApiController]
[AllowAnonymous]
[Route("api/v1")]
public sealed class ContentController : ControllerBase
{
    [HttpGet("blocklist")]
    public async Task<ActionResult<BlocklistResponse>> Blocklist(
        [FromServices] GetBlocklistHandler handler, CancellationToken ct, [FromQuery] DateTime? since = null) =>
        await handler.HandleAsync(since?.AsUtc(), ct);

    [HttpGet("support/resources")]
    public async Task<ActionResult<IReadOnlyList<SupportResourceResponse>>> SupportResources(
        [FromServices] GetSupportResourcesHandler handler, CancellationToken ct) =>
        Ok(await handler.HandleAsync(ct));
}
