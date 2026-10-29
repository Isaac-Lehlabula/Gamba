using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Reclaim.Api.Infrastructure;
using Reclaim.Application.Assessment;
using Reclaim.Application.Common;

namespace Reclaim.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/assessment")]
public sealed class AssessmentController : ControllerBase
{
    /// <summary>The questions are not personal, so the app can show them before an account exists.</summary>
    [AllowAnonymous]
    [HttpGet("questions")]
    public ActionResult<QuestionnaireResponse> Questions([FromServices] GetQuestionnaireHandler handler) => handler.Handle();

    [HttpPost("submit")]
    public async Task<ActionResult<AssessmentResultResponse>> Submit(SubmitAssessmentRequest request, [FromServices] SubmitAssessmentHandler handler, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await handler.HandleAsync(User.GetUserId(), request, ct));

    [HttpGet("history")]
    public async Task<ActionResult<PagedResponse<AssessmentResultResponse>>> History(
        [FromServices] GetAssessmentHistoryHandler handler,
        CancellationToken ct,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = Paging.DefaultPageSize) =>
        await handler.HandleAsync(User.GetUserId(), page, pageSize, ct);
}
