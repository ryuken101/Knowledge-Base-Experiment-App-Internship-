import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' hide Document;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/document.dart';
import '../providers/document_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/document_tree_panel.dart';
import '../widgets/pill_button.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// The live WYSIWYG editor state for the currently loaded document. Rebuilt
  /// from markdown whenever the selection changes to a different document.
  EditorState? _editorState;
  EditorScrollController? _editorScrollController;
  StreamSubscription<EditorTransactionValue>? _txnSub;

  /// Markdown known to be persisted on the server (already passed through the
  /// exporter, so an untouched document reads as clean). The editor is "dirty"
  /// when its exported markdown diverges from this.
  String _savedContent = '';
  bool _dirty = false;

  /// The document whose content is currently seeded into the editor, so we only
  /// rebuild the editor when the selection actually changes to a different one.
  String? _loadedDocId;

  /// True while a save request is in flight.
  bool _mutating = false;

  @override
  void dispose() {
    _disposeEditor();
    super.dispose();
  }

  /// Tear down the current editor (listener + controllers + state) before
  /// building a new one or disposing the screen.
  void _disposeEditor() {
    _txnSub?.cancel();
    _txnSub = null;
    _editorScrollController?.dispose();
    _editorScrollController = null;
    _editorState?.dispose();
    _editorState = null;
  }

  /// Parse stored markdown into an [EditorState]. Empty/whitespace content
  /// yields a blank document with one empty paragraph (AppFlowy needs at least
  /// one node to edit into).
  EditorState _stateFromMarkdown(String content) {
    if (content.trim().isEmpty) {
      return EditorState.blank(withInitialText: true);
    }
    return EditorState(document: markdownToDocument(content));
  }

  /// Adopt [doc] into a fresh editor: build its state from markdown, normalize
  /// the saved baseline through the exporter (so it isn't falsely dirty), and
  /// listen for edits to drive the dirty indicator.
  void _seedEditor(Document doc) {
    _disposeEditor();
    final state = _stateFromMarkdown(doc.content ?? '');
    _editorState = state;
    _editorScrollController = EditorScrollController(editorState: state);
    _savedContent = documentToMarkdown(state.document);
    _dirty = false;
    _loadedDocId = doc.id;
    _txnSub = state.transactionStream.listen((_) {
      if (!mounted) return;
      final md = documentToMarkdown(state.document);
      final dirty = md != _savedContent;
      if (dirty != _dirty) setState(() => _dirty = dirty);
    });
  }

  /// Run a mutation, tracking busy state and surfacing failures as a snackbar
  /// without discarding the editor.
  Future<void> _runMutation(Future<void> Function() action) async {
    setState(() => _mutating = true);
    try {
      await action();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Error: $err')));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  /// Save the current document's content (manual save): export the editor to
  /// markdown and persist it.
  Future<void> _save() async {
    final id = ref.read(selectedDocumentIdProvider);
    final state = _editorState;
    if (id == null || state == null) return;
    await _runMutation(() async {
      final md = documentToMarkdown(state.document);
      await ref.read(documentsProvider.notifier).updateContent(id, md);
      if (!mounted) return;
      setState(() {
        _savedContent = md;
        _dirty = false;
      });
      // Refresh the cached content so a later reselect reads the saved version.
      ref.invalidate(documentContentProvider(id));
    });
  }

  /// Gate switching to another document when the current one has unsaved edits.
  /// Returns true to proceed; shows a Discard/Cancel dialog otherwise. Passed to
  /// [DocumentTreePanel] so a document tap can ask before changing the selection.
  Future<bool> _confirmSwitchAway(String targetId) async {
    if (!_dirty || _loadedDocId == null || _loadedDocId == targetId) return true;
    final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text(
              'This document has unsaved edits. Switching will lose them. '
              'Save first to keep them.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Discard', style: AppType.body(color: AppColors.primary)),
              ),
            ],
          ),
        ) ??
        false;
    return discard;
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final selectedId = ref.watch(selectedDocumentIdProvider);

    final docs = docsAsync.asData?.value;
    Document? selectedDoc;
    if (docs != null && selectedId != null) {
      for (final d in docs) {
        if (d.id == selectedId) {
          selectedDoc = d;
          break;
        }
      }
    }
    final editingDoc =
        (selectedDoc != null && !selectedDoc.isFolder) ? selectedDoc : null;

    final busy = docsAsync.isLoading || _mutating;
    final canSave = editingDoc != null && _dirty && !_mutating;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Text(editingDoc?.title ?? 'Knowledge Base'),
        actions: [
          if (editingDoc != null && _dirty) const _UnsavedBadge(),
          PillButton(
            label: 'Save',
            icon: Icons.save_outlined,
            onPressed: canSave ? _save : null,
          ),
          const SizedBox(width: AppSpacing.lg),
        ],
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.primary,
                  backgroundColor: AppColors.dividerSoft,
                ),
              )
            : null,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 300,
            child: DocumentTreePanel(confirmSwitch: _confirmSwitchAway),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _editorArea(docsAsync, selectedDoc, editingDoc)),
        ],
      ),
    );
  }

  Widget _editorArea(
    AsyncValue<List<Document>> docsAsync,
    Document? selectedDoc,
    Document? editingDoc,
  ) {
    if (docsAsync.hasError && !docsAsync.hasValue) {
      return _ErrorView(
        message: '${docsAsync.error}',
        onRetry: () => ref.invalidate(documentsProvider),
      );
    }
    if (editingDoc != null) {
      return ref.watch(documentContentProvider(editingDoc.id)).when(
            loading: () => _loadedDocId == editingDoc.id
                ? _buildEditor(context)
                : const Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
            error: (err, _) => _ErrorView(
              message: '$err',
              onRetry: () =>
                  ref.invalidate(documentContentProvider(editingDoc.id)),
            ),
            data: (doc) {
              if (_loadedDocId != doc.id) {
                // The editor still holds another document — rebuild it for this
                // one. Done post-frame (can't setState during build); a spinner
                // shows for the frame so the previous content never flashes.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (_loadedDocId == doc.id) return; // already seeded
                  if (ref.read(selectedDocumentIdProvider) != doc.id) return;
                  setState(() => _seedEditor(doc));
                });
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary));
              }
              return _buildEditor(context);
            },
          );
    }
    return _EmptyEditor(
      isFolder: selectedDoc?.isFolder ?? false,
      name: selectedDoc?.title,
    );
  }

  Widget _buildEditor(BuildContext context) {
    final state = _editorState;
    final scroll = _editorScrollController;
    if (state == null || scroll == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return _Pane(
      label: 'Editor',
      background: AppColors.canvas,
      padded: false,
      child: AppFlowyEditor(
        editorState: state,
        editorScrollController: scroll,
        editorStyle: _editorStyle(),
        blockComponentBuilders: standardBlockComponentBuilderMap,
        characterShortcutEvents: standardCharacterShortcutEvents,
        commandShortcutEvents: standardCommandShortcutEvents,
      ),
    );
  }

  /// Editor styling matched to the design system: Action Blue caret/selection,
  /// 17px reading body, monospace inline code.
  EditorStyle _editorStyle() {
    return EditorStyle.desktop(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      cursorColor: AppColors.primary,
      selectionColor: AppColors.primary.withValues(alpha: 0.20),
      textStyleConfiguration: TextStyleConfiguration(
        text: AppType.body(),
        bold: const TextStyle(fontWeight: FontWeight.w600),
        italic: const TextStyle(fontStyle: FontStyle.italic),
        href: const TextStyle(
          color: AppColors.primary,
          decoration: TextDecoration.underline,
        ),
        code: AppType.mono(color: AppColors.inkMuted80),
      ),
    );
  }
}

/// A labelled work surface: a small caption header over a hairline, then content.
class _Pane extends StatelessWidget {
  const _Pane({
    required this.label,
    required this.child,
    required this.background,
    this.padded = true,
  });

  final String label;
  final Widget child;
  final Color background;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Text(
              label,
              style: AppType.captionStrong(color: AppColors.inkMuted48),
            ),
          ),
          Expanded(
            child: padded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    child: child,
                  )
                : child,
          ),
        ],
      ),
    );
  }
}

/// Shown in the editor area when nothing editable is selected: either no
/// selection, or a folder (which holds documents rather than content).
class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor({required this.isFolder, this.name});

  final bool isFolder;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final icon = isFolder ? Icons.folder_open_outlined : Icons.description_outlined;
    final title = isFolder
        ? '"${name ?? 'Folder'}" is a folder'
        : 'No document selected';
    final hint = isFolder
        ? 'Open a document inside it, or use the ⋯ menu to add one.'
        : 'Pick a document from the sidebar, or create one with the + buttons.';
    return Container(
      color: AppColors.canvas,
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.inkMuted48),
            const SizedBox(height: AppSpacing.md),
            Text(title, textAlign: TextAlign.center, style: AppType.bodyStrong()),
            const SizedBox(height: AppSpacing.xs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: AppType.caption(color: AppColors.inkMuted48),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "unsaved changes" marker: an Action Blue dot + caption.
class _UnsavedBadge extends StatelessWidget {
  const _UnsavedBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text('Unsaved', style: AppType.caption(color: AppColors.inkMuted48)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: AppColors.inkMuted48),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not reach the knowledge-base API.',
              textAlign: TextAlign.center,
              style: AppType.bodyStrong(),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppType.caption(color: AppColors.inkMuted48),
            ),
            const SizedBox(height: AppSpacing.lg),
            PillButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
