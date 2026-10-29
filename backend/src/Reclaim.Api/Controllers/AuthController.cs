using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Reclaim.Api.Infrastructure;
using Reclaim.Application.Auth;

namespace Reclaim.Api.Controllers;

[ApiController]
[Route("api/v1/auth")]
public sealed class AuthController : ControllerBase
{
    [HttpPost("register")]
    [EnableRateLimiting(RateLimiting.AuthPolicy)]
    public async Task<ActionResult<AuthResponse>> Register(RegisterRequest request, [FromServices] RegisterHandler handler, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await handler.HandleAsync(request, ct));

    [HttpPost("login")]
    [EnableRateLimiting(RateLimiting.AuthPolicy)]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest request, [FromServices] LoginHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(request, ct);

    [HttpPost("refresh")]
    [EnableRateLimiting(RateLimiting.AuthPolicy)]
    public async Task<ActionResult<AuthResponse>> Refresh(RefreshRequest request, [FromServices] RefreshHandler handler, CancellationToken ct) =>
        await handler.HandleAsync(request, ct);

    [Authorize]
    [HttpPost("logout")]
    public async Task<IActionResult> Logout(LogoutRequest request, [FromServices] LogoutHandler handler, CancellationToken ct)
    {
        await handler.HandleAsync(User.GetUserId(), request, ct);
        return NoContent();
    }

    [Authorize]
    [HttpDelete("account")]
    public async Task<IActionResult> DeleteAccount([FromServices] DeleteAccountHandler handler, CancellationToken ct)
    {
        await handler.HandleAsync(User.GetUserId(), ct);
        return NoContent();
    }
}
