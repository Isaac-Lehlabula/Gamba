using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Reclaim.Application.Common.Abstractions;
using Reclaim.Domain.Auditing;
using Reclaim.Infrastructure.Persistence;

namespace Reclaim.Infrastructure.Auditing;

public sealed class AuditOptions
{
    public const string SectionName = "Audit";

    /// <summary>HMAC key for IP addresses. Keyed because the IPv4 space is small enough to brute-force a plain hash.</summary>
    public string IpHashKey { get; set; } = "";
}

internal sealed class AuditLogger(
    ReclaimDbContext db,
    IRequestContext request,
    IOptions<AuditOptions> options,
    TimeProvider time) : IAuditLogger
{
    public void Record(AuditEventType eventType, Guid? appUserId, object? metadata = null)
    {
        var json = metadata is null ? null : JsonSerializer.Serialize(metadata);
        db.AuditLogs.Add(AuditLog.Record(eventType, appUserId, json, HashIp(request.IpAddress), time.GetUtcNow().UtcDateTime));
    }

    private string? HashIp(string? ip)
    {
        if (string.IsNullOrEmpty(ip))
            return null;
        var mac = HMACSHA256.HashData(Encoding.UTF8.GetBytes(options.Value.IpHashKey), Encoding.UTF8.GetBytes(ip));
        return Convert.ToHexString(mac);
    }
}
