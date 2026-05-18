// The DbContext is EF Core's bridge between the C# classes and the SQLite database.
using KbApp.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace KbApp.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Document> Documents => Set<Document>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Document>(entity =>
        {
            // Indexes for the queries you'll actually run
            entity.HasIndex(d => d.FolderPath);
            entity.HasIndex(d => d.Title);
        });
    }
}