using Microsoft.Extensions.Options;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Infrastructure.Security;

namespace Reclaim.Api.IntegrationTests;

/// <summary>Infrastructure security primitives; these need no database.</summary>
public class SecurityPrimitiveTests
{
    private static Pbkdf2PasswordHasher Hasher(int iterations) =>
        new(Options.Create(new PasswordHashingOptions { Iterations = iterations }));

    [Fact]
    public void Password_hash_verifies_only_the_original_password()
    {
        var hasher = Hasher(1000);
        var hash = hasher.Hash("correct horse");

        Assert.DoesNotContain("correct horse", hash);
        Assert.Equal(PasswordVerificationResult.Success, hasher.Verify("correct horse", hash, hasher.Algorithm));
        Assert.Equal(PasswordVerificationResult.Failed, hasher.Verify("Correct horse", hash, hasher.Algorithm));
        Assert.Equal(PasswordVerificationResult.Failed, hasher.Verify("correct horse", hash, "other-algorithm"));
    }

    [Fact]
    public void Same_password_gets_a_different_salt_each_time()
    {
        var hasher = Hasher(1000);
        Assert.NotEqual(hasher.Hash("correct horse"), hasher.Hash("correct horse"));
    }

    [Fact]
    public void Hash_with_an_older_work_factor_asks_for_rehash()
    {
        var oldHash = Hasher(1000).Hash("correct horse");
        var current = Hasher(2000);
        Assert.Equal(PasswordVerificationResult.SuccessRehashNeeded, current.Verify("correct horse", oldHash, current.Algorithm));
    }

    [Theory]
    [InlineData("")]
    [InlineData("garbage")]
    [InlineData("1000.notbase64!.alsonot")]
    public void Malformed_hash_fails_instead_of_throwing(string stored)
    {
        var hasher = Hasher(1000);
        Assert.Equal(PasswordVerificationResult.Failed, hasher.Verify("x", stored, hasher.Algorithm));
    }

    [Fact]
    public void Refresh_tokens_are_random_and_hash_deterministically()
    {
        var service = new JwtTokenService(Options.Create(new JwtOptions { SigningKey = new string('k', 32) }), TimeProvider.System);
        var a = service.GenerateRefreshToken();

        Assert.NotEqual(a, service.GenerateRefreshToken());
        Assert.Equal(service.HashRefreshToken(a), service.HashRefreshToken(a));
        Assert.NotEqual(a, service.HashRefreshToken(a));
    }
}
