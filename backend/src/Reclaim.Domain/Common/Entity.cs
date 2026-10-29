namespace Reclaim.Domain.Common;

public abstract class Entity
{
    public Guid Id { get; protected set; } = Guid.NewGuid();
    public DateTime CreatedAtUtc { get; protected set; }
    public DateTime UpdatedAtUtc { get; protected set; }

    protected void Touch(DateTime nowUtc) => UpdatedAtUtc = nowUtc;

    /// <summary>Uses a client-generated id when one is supplied, so offline-created records keep their identity on sync.</summary>
    protected void AssignId(Guid? id)
    {
        if (id is { } value && value != Guid.Empty)
            Id = value;
    }

    protected void Stamp(DateTime nowUtc)
    {
        CreatedAtUtc = nowUtc;
        UpdatedAtUtc = nowUtc;
    }
}
