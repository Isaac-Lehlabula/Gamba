using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Reclaim.Api.Infrastructure;
using Reclaim.Application.Profile;

namespace Reclaim.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/profile")]
public sealed class ProfileController : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<ProfileResponse>> Get([FromServices] GetProfileHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(User.GetUserId(), ct);

    [HttpPut]
    public async Task<ActionResult<ProfileResponse>> Update(UpdateProfileRequest request, [FromServices] UpdateProfileHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(User.GetUserId(), request, ct);
}
