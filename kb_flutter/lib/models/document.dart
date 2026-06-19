/// A node in the document tree, mirroring the backend's `DocumentOut` schema
/// (kb_backend/kb_api/server.py) and `kb_program/models.py::Document`.
///
/// A "folder" is just a document that holds children ([isFolder] is a UI/type
/// hint). [parentId] is null for a top-level node; [ownerId] is null for a
/// shared (Team) node. [content] is null in list results and populated by read.
class Document {
  const Document({
    required this.id,
    this.title = 'Untitled',
    this.parentId,
    this.ownerId,
    this.isFolder = false,
    this.position = 0,
    this.content,
    this.createdAt,
    this.updatedAt,
    this.snippet,
  });

  final String id;
  final String title;
  final String? parentId;
  final String? ownerId;
  final bool isFolder;
  final int position;
  final String? content;
  final String? createdAt;
  final String? updatedAt;

  /// Search-only: an excerpt around the matched text, populated by
  /// `/documents/search`. Null everywhere else (tree/list/read).
  final String? snippet;

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Untitled',
      parentId: json['parent_id'] as String?,
      ownerId: json['owner_id'] as String?,
      isFolder: (json['is_folder'] as bool?) ?? false,
      position: (json['position'] as num?)?.toInt() ?? 0,
      content: json['content'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      snippet: json['snippet'] as String?,
    );
  }
}

/// A node in the assembled tree: a [Document] plus its ordered [children].
class DocNode {
  const DocNode(this.doc, this.children);

  final Document doc;
  final List<DocNode> children;
}

/// Assemble a flat document list (as returned by the API) into a tree, ordering
/// siblings by `position` then `id` (stable). Roots are the nodes with a null
/// `parentId`.
List<DocNode> buildDocTree(List<Document> docs) {
  final byParent = <String?, List<Document>>{};
  for (final d in docs) {
    byParent.putIfAbsent(d.parentId, () => <Document>[]).add(d);
  }
  for (final list in byParent.values) {
    list.sort((a, b) =>
        a.position != b.position ? a.position.compareTo(b.position) : a.id.compareTo(b.id));
  }

  List<DocNode> build(String? parentId) {
    final kids = byParent[parentId] ?? const <Document>[];
    return [for (final d in kids) DocNode(d, build(d.id))];
  }

  return build(null);
}
