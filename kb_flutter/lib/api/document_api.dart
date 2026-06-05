import 'package:dio/dio.dart';

import '../models/document.dart';
import 'kb_client.dart' show kKbApiBaseUrl;

/// Thin Dio wrapper over the document-tree REST API (kb_backend/kb_api). One
/// method per route. Document ids contain a colon (`document:abc`); they are
/// embedded directly in the path, which the backend accepts via a `:path` param.
class DocumentApi {
  DocumentApi({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: kKbApiBaseUrl,
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            );

  final Dio _dio;

  /// GET /documents — the tree as a flat list (metadata only, no content).
  Future<List<Document>> list() async {
    final res = await _dio.get<List<dynamic>>('/documents');
    return (res.data ?? const [])
        .map((e) => Document.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /documents/{id} — a single document including its markdown content.
  Future<Document> read(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/documents/$id');
    return Document.fromJson(res.data!);
  }

  /// POST /documents — create a document (or folder) under [parentId], or
  /// top-level if null.
  Future<Document> create({String? title, String? parentId, bool isFolder = false}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/documents',
      data: {'title': title, 'parent_id': parentId, 'is_folder': isFolder},
    );
    return Document.fromJson(res.data!);
  }

  /// PUT /documents/{id} — set content and/or title.
  Future<Document> update(String id, {String? content, String? title}) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/documents/$id',
      data: {
        'content': ?content,
        'title': ?title,
      },
    );
    return Document.fromJson(res.data!);
  }

  /// POST /documents/{id}/move — reparent to [newParentId] (or top-level) at [index].
  Future<Document> move(String id, {String? newParentId, int index = 0}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/documents/$id/move',
      data: {'new_parent_id': newParentId, 'index': index},
    );
    return Document.fromJson(res.data!);
  }

  /// DELETE /documents/{id} — delete the node and its whole subtree.
  Future<void> delete(String id) async {
    await _dio.delete<Map<String, dynamic>>('/documents/$id');
  }
}
