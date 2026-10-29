using FluentValidation;
using Reclaim.Domain.Users;

namespace Reclaim.Application.Auth;

public sealed record RegisterRequest(string Email, string Password, Guid? LocalProfileId);

public sealed record LoginRequest(string Email, string Password);

public sealed record RefreshRequest(string RefreshToken);

public sealed record LogoutRequest(string RefreshToken);

public sealed record AuthResponse(
    Guid UserId,
    string AccessToken,
    DateTime AccessTokenExpiresAtUtc,
    string RefreshToken,
    DateTime RefreshTokenExpiresAtUtc);

public sealed class RegisterRequestValidator : AbstractValidator<RegisterRequest>
{
    public const int MinPasswordLength = 8;
    public const int MaxPasswordLength = 128;

    public RegisterRequestValidator()
    {
        RuleFor(x => x.Email).NotEmpty().EmailAddress().MaximumLength(AppUser.MaxEmailLength);
        RuleFor(x => x.Password).NotEmpty().MinimumLength(MinPasswordLength).MaximumLength(MaxPasswordLength);
    }
}

public sealed class LoginRequestValidator : AbstractValidator<LoginRequest>
{
    public LoginRequestValidator()
    {
        RuleFor(x => x.Email).NotEmpty().MaximumLength(AppUser.MaxEmailLength);
        RuleFor(x => x.Password).NotEmpty().MaximumLength(RegisterRequestValidator.MaxPasswordLength);
    }
}

public sealed class RefreshRequestValidator : AbstractValidator<RefreshRequest>
{
    public RefreshRequestValidator() => RuleFor(x => x.RefreshToken).NotEmpty().MaximumLength(200);
}

public sealed class LogoutRequestValidator : AbstractValidator<LogoutRequest>
{
    public LogoutRequestValidator() => RuleFor(x => x.RefreshToken).NotEmpty().MaximumLength(200);
}
