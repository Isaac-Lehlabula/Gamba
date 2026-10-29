namespace Reclaim.Application.Common.Abstractions;

public interface IPasswordHasher
{
    /// <summary>Identifier stored alongside each hash so the algorithm can be migrated later.</summary>
    string Algorithm { get; }

    string Hash(string password);

    PasswordVerificationResult Verify(string password, string passwordHash, string algorithm);
}

public enum PasswordVerificationResult
{
    Failed,
    Success,
    SuccessRehashNeeded,
}
