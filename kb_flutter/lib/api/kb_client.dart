import 'package:dio/dio.dart';

import '../models/knowledge_base.dart';

/// Base URL of the FastAPI backend (kb_backend/kb_api). Change here to point at
/// a different host. Works for Windows desktop and web (CORS is enabled
/// server-side).
const String kKbApiBaseUrl = 'http://127.0.0.1:8000';

/// Thin Dio wrapper over the knowledge-base REST API. One method per route;
/// each returns the refreshed [KnowledgeBase] (except [deleteFile], which
/// removes the row entirely).
class KbApi {
  KbApi({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: kKbApiBaseUrl,
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            );

  final Dio _dio;

  /// GET /knowledge-base — loads the KB (backend creates an empty one on first read).
  Future<KnowledgeBase> get() async {
    final res = await _dio.get<Map<String, dynamic>>('/knowledge-base');
    return KnowledgeBase.fromJson(res.data!);
  }

  /// PUT /knowledge-base — full replace (manual save).
  Future<KnowledgeBase> save(String content) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/knowledge-base',
      data: {'content': content},
    );
    return KnowledgeBase.fromJson(res.data!);
  }

  /// DELETE /knowledge-base — empties content, keeps the row.
  Future<KnowledgeBase> clear() async {
    final res = await _dio.delete<Map<String, dynamic>>('/knowledge-base');
    return KnowledgeBase.fromJson(res.data!);
  }

  /// DELETE /knowledge-base/file — removes the whole row. A subsequent [get]
  /// recreates an empty KB (create-on-read).
  Future<void> deleteFile() async {
    await _dio.delete<Map<String, dynamic>>('/knowledge-base/file');
  }
}
