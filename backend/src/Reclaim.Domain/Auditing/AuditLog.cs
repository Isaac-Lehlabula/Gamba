using Reclaim.Domain.Common;

namespace Reclaim.Domain.Auditing;

/// <summary>
/// A security-relevant event. Metadata must never contain journal, financial or credential
/// content — only ids, types and outcomes.
/// </summary>
public sealed class AuditLog : Entity
{
    private AuditLog() { }

    public Guid? AppUserId { get; private set; }
    public AuditEventType EventType { get; private set; }
    public string? Metadata { get; private set; }
    public string? IpAddressHash { get; private set; }

    public static AuditLog Record(AuditEventType eventType, Guid? appUserId, string? metadataJson, string? ipAddressHash, DateTime nowUtc)
    {
        var log = new AuditLog
        {
            EventType = eventType,
            AppUserId = appUserId,
            Metadata = metadataJson,
            IpAddressHash = ipAddressHash,
        };
        log.Stamp(nowUtc);
        return log;
    }
}
