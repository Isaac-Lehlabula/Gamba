namespace Reclaim.Domain.Common;

public abstract class Entity
{
    public Guid Id { get; protected set; } = Guid.NewGuid();
    public DateTime CreatedAtUtc { get; protected set; }
    public DateTime UpdatedAtUtc { get; protected set; }

    protected void Touch(DateTime nowUtc) => UpdatedAtUtc = nowUtc;

    protected void Stamp(DateTime nowUtc)
    {
        CreatedAtUtc = nowUtc;
        UpdatedAtUtc = nowUtc;
    }
}
