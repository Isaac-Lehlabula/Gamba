using Reclaim.Application.Auth;
using Reclaim.Application.Common;
using Reclaim.Domain.Auditing;

namespace Reclaim.Application.Tests;

public class AuthHandlerTests
{
    private readonly AuthHarness _h = new();

    private Task<AuthResponse> RegisterAsync(string email = "Someone@Example.com", string password = "correct horse") =>
        _h.Register.HandleAsync(new RegisterRequest(email, password, null));

    [Fact]
    public async Task Register_creates_account_profile_and_session()
    {
        var localId = Guid.NewGuid();
        var response = await _h.Register.HandleAsync(new RegisterRequest("Someone@Example.com", "correct horse", localId));

        var user = Assert.Single(_h.Store.Users);
        Assert.Equal("someone@example.com", user.Email);
        Assert.Equal(user.Id, response.UserId);
        Assert.Equal(localId, Assert.Single(_h.Store.Profiles).LocalProfileId);
        Assert.Equal(_h.Tokens.HashRefreshToken(response.RefreshToken), Assert.Single(_h.Store.Tokens).TokenHash);
        Assert.Contains(AuditEventType.AccountRegistered, _h.Store.Audit);
    }

    [Fact]
    public async Task Register_rejects_an_email_already_in_use_regardless_of_case()
    {
        await RegisterAsync("someone@example.com");
        await Assert.ThrowsAsync<ConflictException>(() => RegisterAsync("  SOMEONE@example.com "));
    }

    [Fact]
    public async Task Login_with_wrong_password_fails_and_is_audited()
    {
        await RegisterAsync();
        await Assert.ThrowsAsync<AuthenticationFailedException>(() =>
            _h.Login.HandleAsync(new LoginRequest("someone@example.com", "wrong password")));
        Assert.Contains(AuditEventType.LoginFailed, _h.Store.Audit);
    }

    [Fact]
    public async Task Login_with_unknown_email_fails_the_same_way()
    {
        await Assert.ThrowsAsync<AuthenticationFailedException>(() =>
            _h.Login.HandleAsync(new LoginRequest("nobody@example.com", "whatever123")));
    }

    [Fact]
    public async Task Login_starts_a_new_token_family()
    {
        var registered = await RegisterAsync();
        var loggedIn = await _h.Login.HandleAsync(new LoginRequest("someone@example.com", "correct horse"));

        Assert.Equal(registered.UserId, loggedIn.UserId);
        Assert.Equal(2, _h.Store.Tokens.Select(t => t.FamilyId).Distinct().Count());
    }

    [Fact]
    public async Task Refresh_rotates_the_token_within_its_family()
    {
        var first = await RegisterAsync();
        var second = await _h.Refresh.HandleAsync(new RefreshRequest(first.RefreshToken));

        Assert.NotEqual(first.RefreshToken, second.RefreshToken);
        var old = _h.Store.Tokens.Single(t => t.TokenHash == _h.Tokens.HashRefreshToken(first.RefreshToken));
        var current = _h.Store.Tokens.Single(t => t.TokenHash == _h.Tokens.HashRefreshToken(second.RefreshToken));
        Assert.True(old.IsRevoked);
        Assert.Equal(current.TokenHash, old.ReplacedByTokenHash);
        Assert.Equal(old.FamilyId, current.FamilyId);
        Assert.False(current.IsRevoked);
    }

    [Fact]
    public async Task Reusing_a_rotated_token_revokes_the_whole_family()
    {
        var first = await RegisterAsync();
        var second = await _h.Refresh.HandleAsync(new RefreshRequest(first.RefreshToken));

        await Assert.ThrowsAsync<AuthenticationFailedException>(() => _h.Refresh.HandleAsync(new RefreshRequest(first.RefreshToken)));
        await Assert.ThrowsAsync<AuthenticationFailedException>(() => _h.Refresh.HandleAsync(new RefreshRequest(second.RefreshToken)));
        Assert.All(_h.Store.Tokens, t => Assert.True(t.IsRevoked));
        Assert.Contains(AuditEventType.RefreshTokenReuseDetected, _h.Store.Audit);
    }

    [Fact]
    public async Task Refresh_fails_once_the_token_has_expired()
    {
        var first = await RegisterAsync();
        _h.Time.Advance(TimeSpan.FromDays(31));
        await Assert.ThrowsAsync<AuthenticationFailedException>(() => _h.Refresh.HandleAsync(new RefreshRequest(first.RefreshToken)));
    }

    [Fact]
    public async Task Refresh_fails_for_an_unknown_token()
    {
        await Assert.ThrowsAsync<AuthenticationFailedException>(() => _h.Refresh.HandleAsync(new RefreshRequest("not-a-token")));
    }

    [Fact]
    public async Task Logout_ends_only_that_session()
    {
        var phone = await RegisterAsync();
        var tablet = await _h.Login.HandleAsync(new LoginRequest("someone@example.com", "correct horse"));

        await _h.Logout.HandleAsync(phone.UserId, new LogoutRequest(phone.RefreshToken));

        await Assert.ThrowsAsync<AuthenticationFailedException>(() => _h.Refresh.HandleAsync(new RefreshRequest(phone.RefreshToken)));
        await _h.Refresh.HandleAsync(new RefreshRequest(tablet.RefreshToken));
    }

    [Fact]
    public async Task Logout_ignores_a_token_belonging_to_someone_else()
    {
        var mine = await RegisterAsync("me@example.com");
        await _h.Logout.HandleAsync(Guid.NewGuid(), new LogoutRequest(mine.RefreshToken));
        Assert.All(_h.Store.Tokens, t => Assert.False(t.IsRevoked));
    }

    [Fact]
    public async Task Deleting_an_account_signs_out_everywhere_and_blocks_login()
    {
        var session = await RegisterAsync();
        await _h.DeleteAccount.HandleAsync(session.UserId);

        Assert.True(_h.Store.Users.Single().IsDeleted);
        Assert.All(_h.Store.Tokens, t => Assert.True(t.IsRevoked));
        await Assert.ThrowsAsync<AuthenticationFailedException>(() =>
            _h.Login.HandleAsync(new LoginRequest("someone@example.com", "correct horse")));
        // Email stays reserved during the grace period.
        await Assert.ThrowsAsync<ConflictException>(() => RegisterAsync());
    }

    [Fact]
    public async Task Purge_only_removes_accounts_past_the_grace_period()
    {
        var session = await RegisterAsync();
        await _h.DeleteAccount.HandleAsync(session.UserId);

        _h.Time.Advance(TimeSpan.FromDays(6));
        Assert.Equal(0, await _h.Purge.HandleAsync());
        Assert.Single(_h.Store.Users);

        _h.Time.Advance(TimeSpan.FromDays(2));
        Assert.Equal(1, await _h.Purge.HandleAsync());
        Assert.Empty(_h.Store.Users);
        Assert.Contains(AuditEventType.AccountPurged, _h.Store.Audit);
    }
}
