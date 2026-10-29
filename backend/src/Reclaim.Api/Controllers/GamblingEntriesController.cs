using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Reclaim.Api.Infrastructure;
using Reclaim.Application.Common;
using Reclaim.Application.GamblingEntries;

namespace Reclaim.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/gambling-entries")]
public sealed class GamblingEntriesController : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<PagedResponse<GamblingEntryResponse>>> List(
        [FromQuery] GamblingEntryQuery query, [FromServices] ListGamblingEntriesHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(User.GetUserId(), query, ct);

    [HttpPost]
    public async Task<ActionResult<GamblingEntryResponse>> Create(SaveGamblingEntryRequest request, [FromServices] CreateGamblingEntryHandler handler, CancellationToken ct)
    {
        var entry = await handler.HandleAsync(User.GetUserId(), request, ct);
        return CreatedAtAction(nameof(List), null, entry);
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<GamblingEntryResponse>> Update(Guid id, SaveGamblingEntryRequest request, [FromServices] UpdateGamblingEntryHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(User.GetUserId(), id, request, ct);

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, [FromServices] DeleteGamblingEntryHandler handler, CancellationToken ct)
    {
        await handler.HandleAsync(User.GetUserId(), id, ct);
        return NoContent();
    }

    /// <param name="timeZone">IANA zone for today/this week/this month; defaults to Africa/Johannesburg.</param>
    [HttpGet("stats")]
    public async Task<ActionResult<GamblingStatsResponse>> Stats([FromServices] GetGamblingStatsHandler handler, CancellationToken ct, [FromQuery] string? timeZone = null) =>
        await handler.HandleAsync(User.GetUserId(), timeZone, ct);
}
