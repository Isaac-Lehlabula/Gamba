using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Reclaim.Api.Infrastructure;
using Reclaim.Application.Onboarding;

namespace Reclaim.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/onboarding-responses")]
public sealed class OnboardingController : ControllerBase
{
    [HttpPost]
    public async Task<ActionResult<OnboardingResponseDto>> Submit(SubmitOnboardingRequest request, [FromServices] SubmitOnboardingHandler handler, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await handler.HandleAsync(User.GetUserId(), request, ct));

    [HttpGet]
    public async Task<ActionResult<OnboardingResponseDto>> GetLatest([FromServices] GetLatestOnboardingHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(User.GetUserId(), ct);
}
