import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/document.dart';
import '../providers/document_providers.dart';
import '../theme/app_theme.dart';
import 'document_tree_row.dart';

/// Index sentinel meaning "append as the last child" — the backend clamps it.
const int _appendIndex = 1 << 30;

/// The left sidebar: the document tree on a parchment canvas. Owns expansion and
/// inline-rename state; drives selection, creation, rename, delete and
/// drag-to-move through [documentsProvider] / [selectedDocumentIdProvider].
class DocumentTreePanel extends ConsumerStatefulWidget {
  const DocumentTreePanel({super.key, this.confirmSwitch});

  /// Asked before selecting a different document, so the editor can warn about
  /// unsaved changes. Returns true to proceed with the switch, false to cancel.
  final Future<bool> Function(String targetDocId)? confirmSwitch;

  @override
  ConsumerState<DocumentTreePanel> createState() => _DocumentTreePanelState();
}

/// A flattened, visible tree row: the document, its depth, its parent, and its
/// index among siblings (for "insert before" drop math).
class _Flat {
  const _Flat(this.doc, this.depth, this.parentId, this.siblingIndex);

  final Document doc;
  final int depth;
  final String? parentId;
  final int siblingIndex;
}

class _DocumentTreePanelState extends ConsumerState<DocumentTreePanel> {
  /// Folders listed here are collapsed; everything else is expanded by default.
  final Set<String> _collapsed = {};

  String? _renamingId;
  final _renameController = TextEditingController();

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  // ---- flattening ------------------------------------------------------

  List<_Flat> _flatten(List<DocNode> nodes, int depth, String? parentId) {
    final out = <_Flat>[];
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      out.add(_Flat(n.doc, depth, parentId, i));
      final open = !_collapsed.contains(n.doc.id);
      if (n.doc.isFolder && open && n.children.isNotEmpty) {
        out.addAll(_flatten(n.children, depth + 1, n.doc.id));
      }
    }
    return out;
  }

  /// True if making [targetId] the new parent of [draggedId] would create a
  /// cycle (target is the node itself or one of its descendants).
  bool _wouldCycle(String draggedId, String? targetId, Map<String, String?> parentOf) {
    String? cur = targetId;
    while (cur != null) {
      if (cur == draggedId) return true;
      cur = parentOf[cur];
    }
    return false;
  }

  // ---- mutations -------------------------------------------------------

  Future<void> _select(Document doc) async {
    if (doc.isFolder) {
      // Folders just toggle expansion (and highlight); they never reseed the
      // editor, so unsaved edits in the open document are preserved.
      setState(() {
        if (_collapsed.contains(doc.id)) {
          _collapsed.remove(doc.id);
        } else {
          _collapsed.add(doc.id);
        }
      });
      ref.read(selectedDocumentIdProvider.notifier).select(doc.id);
      return;
    }
    // Switching to a different document: let the editor warn about unsaved edits.
    final confirm = widget.confirmSwitch;
    if (confirm != null && !await confirm(doc.id)) return;
    ref.read(selectedDocumentIdProvider.notifier).select(doc.id);
  }

  void _toggle(Document doc) {
    setState(() {
      if (_collapsed.contains(doc.id)) {
        _collapsed.remove(doc.id);
      } else {
        _collapsed.add(doc.id);
      }
    });
  }

  Future<void> _create({String? parentId, required bool isFolder}) async {
    try {
      final doc = await ref.read(documentsProvider.notifier).create(
            title: isFolder ? 'New folder' : 'Untitled',
            parentId: parentId,
            isFolder: isFolder,
          );
      if (parentId != null) setState(() => _collapsed.remove(parentId));
      if (!isFolder) ref.read(selectedDocumentIdProvider.notifier).select(doc.id);
      _startRename(doc);
    } catch (err) {
      _snack('Error: $err');
    }
  }

  void _startRename(Document doc) {
    setState(() {
      _renamingId = doc.id;
      _renameController.text = doc.title;
    });
  }

  Future<void> _submitRename(String id, String title) async {
    final trimmed = title.trim();
    final current = _renamingId;
    setState(() => _renamingId = null);
    if (current != id || trimmed.isEmpty) return;
    try {
      await ref.read(documentsProvider.notifier).rename(id, trimmed);
    } catch (err) {
      _snack('Error: $err');
    }
  }

  void _cancelRename() => setState(() => _renamingId = null);

  Future<void> _delete(Document doc) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete "${doc.title}"?'),
            content: Text(
              doc.isFolder
                  ? 'This deletes the folder and everything inside it. This cannot be undone.'
                  : 'This permanently deletes the document. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete', style: AppType.body(color: AppColors.primary)),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final selected = ref.read(selectedDocumentIdProvider);
    try {
      await ref.read(documentsProvider.notifier).delete(doc.id);
      if (selected == doc.id) {
        ref.read(selectedDocumentIdProvider.notifier).select(null);
      }
    } catch (err) {
      _snack('Error: $err');
    }
  }

  Future<void> _move(String draggedId, String? parentId, int index) async {
    if (draggedId == parentId) return;
    try {
      await ref
          .read(documentsProvider.notifier)
          .move(draggedId, newParentId: parentId, index: index);
    } catch (err) {
      _snack('Error: $err');
    }
  }

  void _onMenu(Document doc, DocMenuAction action) {
    switch (action) {
      case DocMenuAction.newDocument:
        _create(parentId: doc.id, isFolder: false);
      case DocMenuAction.newFolder:
        _create(parentId: doc.id, isFolder: true);
      case DocMenuAction.rename:
        _startRename(doc);
      case DocMenuAction.delete:
        _delete(doc);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final selectedId = ref.watch(selectedDocumentIdProvider);

    return Container(
      color: AppColors.parchment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const Divider(height: 1, thickness: 1, color: AppColors.hairline),
          Expanded(
            child: docsAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text('Could not load documents.\n$err',
                    style: AppType.caption(color: AppColors.inkMuted48)),
              ),
              data: (docs) => _tree(docs, selectedId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.xs, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text('Documents', style: AppType.captionStrong(color: AppColors.inkMuted48)),
          ),
          IconButton(
            tooltip: 'New document',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: AppColors.inkMuted48,
            icon: const Icon(Icons.note_add_outlined),
            onPressed: () => _create(parentId: null, isFolder: false),
          ),
          IconButton(
            tooltip: 'New folder',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: AppColors.inkMuted48,
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _create(parentId: null, isFolder: true),
          ),
        ],
      ),
    );
  }

  Widget _tree(List<Document> docs, String? selectedId) {
    if (docs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('No documents yet.\nUse + above to create one.',
            style: AppType.caption(color: AppColors.inkMuted48)),
      );
    }
    final tree = buildDocTree(docs);
    final flats = _flatten(tree, 0, null);
    final parentOf = {for (final d in docs) d.id: d.parentId};

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        for (final f in flats) _entry(f, selectedId, parentOf),
        // Trailing drop zone to append at the top level's end.
        _gap(null, tree.length, parentOf),
      ],
    );
  }

  /// One row preceded by its "insert before" drop gap.
  Widget _entry(_Flat f, String? selectedId, Map<String, String?> parentOf) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _gap(f.parentId, f.siblingIndex, parentOf),
        _draggableRow(f, selectedId, parentOf),
      ],
    );
  }

  /// A thin reorder drop target between rows. Dropping here moves the dragged
  /// document to `(parentId, index)`.
  Widget _gap(String? parentId, int index, Map<String, String?> parentOf) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data.isNotEmpty && !_wouldCycle(d.data, parentId, parentOf),
      onAcceptWithDetails: (d) => _move(d.data, parentId, index),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return Container(
          height: active ? 8 : 4,
          alignment: Alignment.center,
          child: active
              ? Container(height: 2, color: AppColors.primary)
              : const SizedBox.shrink(),
        );
      },
    );
  }

  /// The row itself: draggable, and (for folders) a move-into drop target.
  Widget _draggableRow(_Flat f, String? selectedId, Map<String, String?> parentOf) {
    final doc = f.doc;
    final row = DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          doc.isFolder && d.data != doc.id && !_wouldCycle(d.data, doc.id, parentOf),
      onAcceptWithDetails: (d) => _move(d.data, doc.id, _appendIndex),
      builder: (context, candidate, rejected) {
        return DocumentTreeRow(
          doc: doc,
          depth: f.depth,
          selected: selectedId == doc.id,
          expanded: !_collapsed.contains(doc.id),
          dropHighlighted: candidate.isNotEmpty,
          isRenaming: _renamingId == doc.id,
          renameController: _renameController,
          onTap: () => _select(doc),
          onToggle: () => _toggle(doc),
          onMenu: (action) => _onMenu(doc, action),
          onRenameSubmit: (title) => _submitRename(doc.id, title),
          onRenameCancel: _cancelRename,
        );
      },
    );

    return Draggable<String>(
      data: doc.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _dragFeedback(doc),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: row,
    );
  }

  Widget _dragFeedback(Document doc) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.canvas,
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              doc.isFolder ? Icons.folder_outlined : Icons.description_outlined,
              size: 14,
              color: AppColors.inkMuted48,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(doc.title.isEmpty ? 'Untitled' : doc.title,
                style: AppType.caption(color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}
