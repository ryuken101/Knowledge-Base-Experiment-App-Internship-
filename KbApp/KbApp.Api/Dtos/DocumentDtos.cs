namespace KbApp.Api.Dtos;

// What the client sends when creating
public record CreateDocumentDto(string Title, string Content, string FolderPath);

// What the client sends when updating
public record UpdateDocumentDto(string Title, string Content, string FolderPath);

// What the API returns
public record DocumentDto(
    int Id,
    string Title,
    string Content,
    string FolderPath,
    DateTime CreatedAt,
    DateTime UpdatedAt);

// Lightweight version for listings — no Content
public record DocumentSummaryDto(
    int Id,
    string Title,
    string FolderPath,
    DateTime UpdatedAt);