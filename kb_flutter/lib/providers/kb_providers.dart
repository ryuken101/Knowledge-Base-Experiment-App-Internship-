import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/kb_client.dart';
import '../models/knowledge_base.dart';

/// The REST client singleton.
final kbApiProvider = Provider<KbApi>((ref) => KbApi());

/// Loads and mutates the single knowledge-base file. `build()` fetches it (its
/// loading/error states drive the initial screen). The mutation methods fold
/// the refreshed row into state on success and rethrow on failure, so the UI
/// can show a transient error without discarding the editor contents.
final kbProvider =
    AsyncNotifierProvider<KbNotifier, KnowledgeBase>(KbNotifier.new);

class KbNotifier extends AsyncNotifier<KnowledgeBase> {
  KbApi get _api => ref.read(kbApiProvider);

  @override
  Future<KnowledgeBase> build() => _api.get();

  /// Replace the whole file (manual save).
  Future<void> save(String content) async {
    state = AsyncData(await _api.save(content));
  }

  /// Empty the content, keeping the row.
  Future<void> clear() async {
    state = AsyncData(await _api.clear());
  }

  /// Delete the whole row, then re-read (create-on-read yields an empty KB).
  Future<void> deleteFile() async {
    await _api.deleteFile();
    state = AsyncData(await _api.get());
  }
}
