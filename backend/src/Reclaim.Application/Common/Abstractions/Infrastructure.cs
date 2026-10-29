using Reclaim.Domain.Auditing;

namespace Reclaim.Application.Common.Abstractions;

/// <summary>Details of the current request that use cases may need for auditing.</summary>
public interface IRequestContext
{
    string? IpAddress { get; }
}

public interface IAuditLogger
{
    /// <summary>
    /// Stages an audit entry; it is persisted with the next <see cref="IUnitOfWork.SaveChangesAsync"/>.
    /// <paramref name="metadata"/> must contain only ids, types and outcomes — never user content.
    /// </summary>
    void Record(AuditEventType eventType, Guid? appUserId, object? metadata = null);
}

public interface IUnitOfWork
{
    Task SaveChangesAsync(CancellationToken cancellationToken = default);
}
