import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/document_api.dart';
import '../models/document.dart';

/// The document REST client singleton.
final documentApiProvider = Provider<DocumentApi>((ref) => DocumentApi());

/// Loads and mutates the document tree. `build()` fetches the flat list (its
/// loading/error states drive the sidebar). Every mutation re-lists afterwards
/// so the tree stays authoritative; failures rethrow so callers can surface a
/// transient error without losing local state.
final documentsProvider =
    AsyncNotifierProvider<DocumentsNotifier, List<Document>>(DocumentsNotifier.new);

class DocumentsNotifier extends AsyncNotifier<List<Document>> {
  DocumentApi get _api => ref.read(documentApiProvider);

  @override
  Future<List<Document>> build() => _api.list();

  /// Create a document/folder and refresh; returns the created node so the
  /// caller can select/rename it.
  Future<Document> create({String? title, String? parentId, bool isFolder = false}) async {
    final doc = await _api.create(title: title, parentId: parentId, isFolder: isFolder);
    state = AsyncData(await _api.list());
    return doc;
  }

  Future<void> rename(String id, String title) async {
    await _api.update(id, title: title);
    state = AsyncData(await _api.list());
  }

  /// Save a document's markdown content (manual save).
  Future<void> updateContent(String id, String content) async {
    await _api.update(id, content: content);
    state = AsyncData(await _api.list());
  }

  Future<void> move(String id, {String? newParentId, int index = 0}) async {
    await _api.move(id, newParentId: newParentId, index: index);
    state = AsyncData(await _api.list());
  }

  Future<void> delete(String id) async {
    await _api.delete(id);
    state = AsyncData(await _api.list());
  }
}

/// The id of the document currently open in the editor (null = nothing selected).
final selectedDocumentIdProvider =
    NotifierProvider<SelectedDocumentId, String?>(SelectedDocumentId.new);

class SelectedDocumentId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

/// Loads a single document's content for the editor. Keyed by id so switching
/// documents loads the right one; invalidate after a save to refresh.
final documentContentProvider = FutureProvider.family<Document, String>((ref, id) {
  return ref.read(documentApiProvider).read(id);
});

/// The current sidebar search text (empty = not searching, show the tree). The
/// panel debounces keystrokes before writing here.
final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String value) => state = value;
}

/// Search results for the current [searchQueryProvider]; empty list for a blank
/// query (so no request fires until the user actually types).
final searchResultsProvider = FutureProvider.autoDispose<List<Document>>((ref) async {
  final q = ref.watch(searchQueryProvider).trim();
  if (q.isEmpty) return const [];
  return ref.read(documentApiProvider).search(q);
});
