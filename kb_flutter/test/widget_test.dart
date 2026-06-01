// Smoke test: the app builds and shows its title bar, with the network layer
// stubbed so the test does no real I/O.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kb_flutter/api/kb_client.dart';
import 'package:kb_flutter/main.dart';
import 'package:kb_flutter/models/knowledge_base.dart';
import 'package:kb_flutter/providers/kb_providers.dart';

/// In-memory KbApi — no Dio, no timers.
class _FakeKbApi implements KbApi {
  String _content = '# Hello';

  @override
  Future<KnowledgeBase> get() async => KnowledgeBase(content: _content);

  @override
  Future<KnowledgeBase> save(String content) async {
    _content = content;
    return KnowledgeBase(content: _content);
  }

  @override
  Future<KnowledgeBase> clear() async {
    _content = '';
    return const KnowledgeBase(content: '');
  }

  @override
  Future<void> deleteFile() async {
    _content = '';
  }
}

void main() {
  testWidgets('App renders the Knowledge Base title and loaded content',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [kbApiProvider.overrideWithValue(_FakeKbApi())],
        child: const KbApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Knowledge Base'), findsOneWidget);
    // The fake's content loaded into the editor / preview.
    expect(find.text('# Hello'), findsWidgets);
  });
}
