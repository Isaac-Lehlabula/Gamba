using System.Security.Cryptography;
using Microsoft.Extensions.Options;
using Reclaim.Application.Common.Abstractions;

namespace Reclaim.Infrastructure.Security;

public sealed class PasswordHashingOptions
{
    public const string SectionName = "PasswordHashing";

    /// <summary>OWASP's 2023+ recommendation for PBKDF2-HMAC-SHA256. Lowered only in tests.</summary>
    public int Iterations { get; set; } = 600_000;
}

/// <summary>
/// PBKDF2-HMAC-SHA256 with a random per-password salt. Hashes are stored as
/// <c>{iterations}.{base64 salt}.{base64 hash}</c> so the work factor can be raised over time;
/// verifying an older, cheaper hash reports <see cref="PasswordVerificationResult.SuccessRehashNeeded"/>.
/// </summary>
internal sealed class Pbkdf2PasswordHasher(IOptions<PasswordHashingOptions> options) : IPasswordHasher
{
    private const int SaltSize = 16;
    private const int HashSize = 32;
    private static readonly HashAlgorithmName Prf = HashAlgorithmName.SHA256;

    public string Algorithm => "PBKDF2-SHA256";

    public string Hash(string password)
    {
        var iterations = options.Value.Iterations;
        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, Prf, HashSize);
        return $"{iterations}.{Convert.ToBase64String(salt)}.{Convert.ToBase64String(hash)}";
    }

    public PasswordVerificationResult Verify(string password, string passwordHash, string algorithm)
    {
        if (algorithm != Algorithm)
            return PasswordVerificationResult.Failed;

        var parts = passwordHash.Split('.');
        if (parts.Length != 3 || !int.TryParse(parts[0], out var iterations) || iterations <= 0)
            return PasswordVerificationResult.Failed;

        byte[] salt, expected;
        try
        {
            salt = Convert.FromBase64String(parts[1]);
            expected = Convert.FromBase64String(parts[2]);
        }
        catch (FormatException)
        {
            return PasswordVerificationResult.Failed;
        }

        var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, Prf, expected.Length);
        if (!CryptographicOperations.FixedTimeEquals(actual, expected))
            return PasswordVerificationResult.Failed;

        return iterations < options.Value.Iterations
            ? PasswordVerificationResult.SuccessRehashNeeded
            : PasswordVerificationResult.Success;
    }
}
