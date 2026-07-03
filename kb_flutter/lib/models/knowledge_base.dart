/// The single per-user knowledge base file, mirroring the backend's
/// `KnowledgeBaseOut` schema (kb_backend/kb_api/server.py) and
/// `kb_program/models.py::KnowledgeBase`.
class KnowledgeBase {
  const KnowledgeBase({
    this.userId,
    this.content = '',
    this.createdAt,
    this.updatedAt,
  });

  final String? userId;
  final String content;
  final String? createdAt;
  final String? updatedAt;

  factory KnowledgeBase.fromJson(Map<String, dynamic> json) {
    return KnowledgeBase(
      userId: json['user_id'] as String?,
      content: (json['content'] as String?) ?? '',
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }
}
