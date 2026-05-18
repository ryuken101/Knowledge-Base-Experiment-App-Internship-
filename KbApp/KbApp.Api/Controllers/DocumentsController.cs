using KbApp.Api.Data;
using KbApp.Api.Dtos;
using KbApp.Api.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace KbApp.Api.Controllers;

[ApiController]
[Route("api/[controller]")] // → /api/documents
public class DocumentsController : ControllerBase
{
    private readonly AppDbContext _db;

    public DocumentsController(AppDbContext db) => _db = db;

    // GET /api/documents  — list summaries, optional folder filter
    [HttpGet]
    public async Task<ActionResult<IEnumerable<DocumentSummaryDto>>> List(
        [FromQuery] string? folderPath)
    {
        var query = _db.Documents.AsNoTracking();
        if (!string.IsNullOrEmpty(folderPath))
            query = query.Where(d => d.FolderPath == folderPath);

        var items = await query
            .OrderBy(d => d.FolderPath).ThenBy(d => d.Title)
            .Select(d => new DocumentSummaryDto(d.Id, d.Title, d.FolderPath, d.UpdatedAt))
            .ToListAsync();

        return Ok(items);
    }

    // GET /api/documents/5
    [HttpGet("{id:int}")]
    public async Task<ActionResult<DocumentDto>> Get(int id)
    {
        var doc = await _db.Documents.FindAsync(id);
        if (doc is null) return NotFound();
        return Ok(ToDto(doc));
    }

    // POST /api/documents
    [HttpPost]
    public async Task<ActionResult<DocumentDto>> Create(CreateDocumentDto dto)
    {
        var doc = new Document
        {
            Title = dto.Title,
            Content = dto.Content,
            FolderPath = NormalizeFolderPath(dto.FolderPath),
        };
        _db.Documents.Add(doc);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(Get), new { id = doc.Id }, ToDto(doc));
    }

    // PUT /api/documents/5
    [HttpPut("{id:int}")]
    public async Task<ActionResult<DocumentDto>> Update(int id, UpdateDocumentDto dto)
    {
        var doc = await _db.Documents.FindAsync(id);
        if (doc is null) return NotFound();

        doc.Title = dto.Title;
        doc.Content = dto.Content;
        doc.FolderPath = NormalizeFolderPath(dto.FolderPath);
        doc.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(ToDto(doc));
    }

    // DELETE /api/documents/5
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var doc = await _db.Documents.FindAsync(id);
        if (doc is null) return NotFound();
        _db.Documents.Remove(doc);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // GET /api/documents/folders — list all unique folder paths (for tree UI)
    [HttpGet("folders")]
    public async Task<ActionResult<IEnumerable<string>>> Folders()
    {
        var folders = await _db.Documents
            .Select(d => d.FolderPath)
            .Distinct()
            .OrderBy(p => p)
            .ToListAsync();
        return Ok(folders);
    }

    private static DocumentDto ToDto(Document d) =>
        new(d.Id, d.Title, d.Content, d.FolderPath, d.CreatedAt, d.UpdatedAt);

    private static string NormalizeFolderPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return "/";
        path = path.Trim();
        if (!path.StartsWith('/')) path = "/" + path;
        if (path.Length > 1 && path.EndsWith('/')) path = path[..^1];
        return path;
    }
}