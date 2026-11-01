using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Reclaim.Application.Journal;
using Reclaim.Domain.Journal;
using Reclaim.Domain.Urges;
using Reclaim.Domain.Users;
using Reclaim.Infrastructure.Security;

namespace Reclaim.Infrastructure.Persistence;

internal sealed class JournalEntryConfiguration(FieldEncryptor encryptor) : IEntityTypeConfiguration<JournalEntry>
{
    public void Configure(EntityTypeBuilder<JournalEntry> b)
    {
        b.ToTable("JournalEntry");
        b.HasKey(x => x.Id);
        b.Property(x => x.Id).ValueGeneratedNever();
        b.PrimitiveCollection(x => x.Helped).ElementType(e => e.HasConversion<string>());
        b.Property(x => x.Note).HasConversion(new EncryptedStringConverter(encryptor));
        b.HasIndex(x => new { x.UserProfileId, x.OccurredAtUtc });
        b.HasOne<UserProfile>().WithMany().HasForeignKey(x => x.UserProfileId).OnDelete(DeleteBehavior.Cascade);
        b.Ignore(x => x.HadUrge);
    }
}

internal sealed class JournalRepository(ReclaimDbContext db) : IJournalRepository
{
    public Task<JournalEntry?> GetAsync(Guid id, Guid userProfileId, CancellationToken ct = default) =>
        db.JournalEntries.FirstOrDefaultAsync(x => x.Id == id && x.UserProfileId == userProfileId, ct);

    public Task<bool> ExistsAsync(Guid id, CancellationToken ct = default) => db.JournalEntries.AnyAsync(x => x.Id == id, ct);

    public async Task<(IReadOnlyList<JournalEntry> Items, int TotalCount)> GetPageAsync(Guid userProfileId, int page, int pageSize, CancellationToken ct = default)
    {
        var query = db.JournalEntries.Where(x => x.UserProfileId == userProfileId);
        var total = await query.CountAsync(ct);
        var items = await query.OrderByDescending(x => x.OccurredAtUtc).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        return (items, total);
    }

    public async Task<IReadOnlyList<JournalEntry>> GetAllAsync(Guid userProfileId, CancellationToken ct = default) =>
        await db.JournalEntries.Where(x => x.UserProfileId == userProfileId).ToListAsync(ct);

    public async Task<IReadOnlyList<Urge>> GetCompletedUrgesAsync(Guid userProfileId, CancellationToken ct = default) =>
        await db.Urges.Where(x => x.UserProfileId == userProfileId && x.Outcome != UrgeOutcome.Abandoned).ToListAsync(ct);

    public void Add(JournalEntry entry) => db.JournalEntries.Add(entry);

    public void Remove(JournalEntry entry) => db.JournalEntries.Remove(entry);
}
