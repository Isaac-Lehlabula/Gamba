using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Reclaim.Api.Infrastructure;
using Reclaim.Application.Common;
using Reclaim.Application.Journal;

namespace Reclaim.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/journal-entries")]
public sealed class JournalController(JournalHandlers journal) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<PagedResponse<JournalEntryResponse>>> List(
        CancellationToken ct, [FromQuery] int page = 1, [FromQuery] int pageSize = Paging.DefaultPageSize) =>
        await journal.ListAsync(User.GetUserId(), page, pageSize, ct);

    [HttpPost]
    public async Task<ActionResult<JournalEntryResponse>> Create(SaveJournalEntryRequest request, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await journal.CreateAsync(User.GetUserId(), request, ct));

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<JournalEntryResponse>> Update(Guid id, SaveJournalEntryRequest request, CancellationToken ct) =>
        await journal.UpdateAsync(User.GetUserId(), id, request, ct);

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        await journal.DeleteAsync(User.GetUserId(), id, ct);
        return NoContent();
    }

    /// <param name="timeZone">IANA zone used for times of day; defaults to Africa/Johannesburg.</param>
    [HttpGet("insights")]
    public async Task<ActionResult<JournalInsightsResponse>> Insights(CancellationToken ct, [FromQuery] string? timeZone = null) =>
        await journal.InsightsAsync(User.GetUserId(), timeZone, ct);
}
