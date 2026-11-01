using Reclaim.Domain.Common;
using Reclaim.Domain.Gambling;

namespace Reclaim.Domain.Content;

public enum BlocklistSource
{
    Curated,
    UserSubmitted,
}

/// <summary>
/// A gambling domain in the shared blocklist. Rows are never hard-deleted: deactivating keeps
/// the change visible to clients syncing with <c>?since=</c>.
/// </summary>
public sealed class BlocklistDomain : Entity
{
    public const int MaxDomainLength = 253;

    private BlocklistDomain() { }

    public string Domain { get; private set; } = null!;
    public GamblingType Category { get; private set; }
    public BlocklistSource Source { get; private set; }
    public bool IsActive { get; private set; }

    public static BlocklistDomain Create(string domain, GamblingType category, BlocklistSource source, DateTime nowUtc)
    {
        var entry = new BlocklistDomain { Domain = Normalize(domain), Category = category, Source = source, IsActive = true };
        entry.Stamp(nowUtc);
        return entry;
    }

    public void SetActive(bool active, DateTime nowUtc)
    {
        if (IsActive == active) return;
        IsActive = active;
        Touch(nowUtc);
    }

    /// <summary>Lower-case host name without scheme, path or a leading "www.".</summary>
    public static string Normalize(string domain)
    {
        var d = domain.Trim().ToLowerInvariant();
        if (d.Contains("://")) d = d[(d.IndexOf("://", StringComparison.Ordinal) + 3)..];
        var slash = d.IndexOfAny(['/', '?', '#']);
        if (slash >= 0) d = d[..slash];
        d = d.TrimEnd('.');
        if (d.StartsWith("www.", StringComparison.Ordinal)) d = d[4..];

        if (d.Length is 0 or > MaxDomainLength || !d.Contains('.') ||
            d.Split('.').Any(label => label.Length is 0 or > 63 || !label.All(c => char.IsAsciiLetterOrDigit(c) || c == '-') || label.StartsWith('-') || label.EndsWith('-')))
            throw new DomainException($"'{domain}' is not a valid domain.");
        return d;
    }
}

public enum SupportCategory
{
    GamblingSupport,
    Counselling,
    SelfExclusion,
    FinancialCounselling,
    Emergency,
}

/// <summary>
/// A support service shown in the app. Only rows marked verified are ever returned to
/// clients; contact details are added by a person who has checked them, never guessed.
/// </summary>
public sealed class SupportResource : Entity
{
    private SupportResource() { }

    public string Name { get; private set; } = null!;
    public SupportCategory Category { get; private set; }
    public string Description { get; private set; } = null!;
    public string? PhoneNumber { get; private set; }
    public string? Website { get; private set; }
    public string Region { get; private set; } = "South Africa";
    public bool IsVerified { get; private set; }
    public DateTime? VerifiedAtUtc { get; private set; }

    public static SupportResource Create(string name, SupportCategory category, string description, string? phone, string? website, string region, DateTime nowUtc)
    {
        if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(description))
            throw new DomainException("Name and description are required.");
        if (phone is null && website is null)
            throw new DomainException("A support resource needs a phone number or a website.");
        var resource = new SupportResource
        {
            Name = name.Trim(),
            Category = category,
            Description = description.Trim(),
            PhoneNumber = phone?.Trim(),
            Website = website?.Trim(),
            Region = region.Trim(),
        };
        resource.Stamp(nowUtc);
        return resource;
    }

    /// <summary>Records that someone has checked the contact details are current and correct.</summary>
    public void MarkVerified(DateTime nowUtc)
    {
        IsVerified = true;
        VerifiedAtUtc = nowUtc;
        Touch(nowUtc);
    }
}
