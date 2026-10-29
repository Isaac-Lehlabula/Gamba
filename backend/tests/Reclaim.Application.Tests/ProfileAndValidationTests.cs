using Reclaim.Application.Auth;
using Reclaim.Application.Profile;
using Reclaim.Domain.Common;
using Reclaim.Domain.Users;

namespace Reclaim.Application.Tests;

public class ProfileAndValidationTests
{
    private readonly AuthHarness _h = new();

    [Fact]
    public async Task Update_profile_trims_name_and_reads_offsetless_dates_as_utc()
    {
        var session = await _h.Register.HandleAsync(new RegisterRequest("a@example.com", "correct horse", null));
        var handler = new UpdateProfileHandler(_h.Store, _h.Store, _h.Time);

        var start = new DateTime(2026, 9, 1, 0, 0, 0, DateTimeKind.Unspecified);
        var result = await handler.HandleAsync(session.UserId, new UpdateProfileRequest("  Sam  ", RecoveryGoalType.Reduce, start));

        Assert.Equal("Sam", result.DisplayName);
        Assert.Equal(RecoveryGoalType.Reduce, result.RecoveryGoalType);
        Assert.Equal(DateTimeKind.Utc, result.QuitOrReductionStartDateUtc!.Value.Kind);
        Assert.Equal(start.Ticks, result.QuitOrReductionStartDateUtc.Value.Ticks);
    }

    [Fact]
    public void Profile_rejects_a_future_start_date()
    {
        var now = new DateTime(2026, 10, 1, 0, 0, 0, DateTimeKind.Utc);
        var profile = UserProfile.CreateForAccount(Guid.NewGuid(), null, now);
        Assert.Throws<DomainException>(() => profile.Update(null, null, now.AddDays(1), now));
    }

    [Fact]
    public void Profile_without_a_local_id_gets_one()
    {
        var profile = UserProfile.CreateForAccount(Guid.NewGuid(), Guid.Empty, DateTime.UtcNow);
        Assert.NotEqual(Guid.Empty, profile.LocalProfileId);
    }

    [Theory]
    [InlineData("not-an-email", "correct horse")]
    [InlineData("a@example.com", "short")]
    [InlineData("", "correct horse")]
    public void Register_validator_rejects_bad_input(string email, string password)
    {
        var result = new RegisterRequestValidator().Validate(new RegisterRequest(email, password, null));
        Assert.False(result.IsValid);
    }

    [Fact]
    public void Register_validator_accepts_good_input()
    {
        Assert.True(new RegisterRequestValidator().Validate(new RegisterRequest("a@example.com", "correct horse", null)).IsValid);
    }

    [Fact]
    public void Profile_validator_rejects_future_dates_and_long_names()
    {
        var validator = new UpdateProfileRequestValidator(_h.Time);
        var future = _h.Time.GetUtcNow().UtcDateTime.AddDays(1);

        Assert.False(validator.Validate(new UpdateProfileRequest(null, null, future)).IsValid);
        Assert.False(validator.Validate(new UpdateProfileRequest(new string('x', 61), null, null)).IsValid);
        Assert.True(validator.Validate(new UpdateProfileRequest("Sam", RecoveryGoalType.Stop, null)).IsValid);
    }
}
