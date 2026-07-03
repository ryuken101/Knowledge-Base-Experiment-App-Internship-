import 'package:flutter/material.dart';

import '../models/document.dart';
import '../theme/app_theme.dart';

/// Actions available from a tree row's overflow (⋯) menu.
enum DocMenuAction { newDocument, newFolder, rename, delete }

/// One visual row in the document tree: indent + chevron (folders) + icon +
/// title (or an inline rename field) + a hover/selected overflow menu. Purely
/// presentational — the panel owns selection, expansion and mutation state and
/// drives this via callbacks. Drag-and-drop is wired by the panel around this.
class DocumentTreeRow extends StatefulWidget {
  const DocumentTreeRow({
    super.key,
    required this.doc,
    required this.depth,
    required this.selected,
    required this.expanded,
    required this.dropHighlighted,
    required this.isRenaming,
    required this.renameController,
    required this.onTap,
    required this.onToggle,
    required this.onMenu,
    required this.onRenameSubmit,
    required this.onRenameCancel,
  });

  final Document doc;
  final int depth;
  final bool selected;
  final bool expanded;

  /// True while a doc is being dragged over this folder (move-into target).
  final bool dropHighlighted;

  final bool isRenaming;
  final TextEditingController renameController;

  final VoidCallback onTap;
  final VoidCallback onToggle;
  final void Function(DocMenuAction action) onMenu;
  final void Function(String title) onRenameSubmit;
  final VoidCallback onRenameCancel;

  @override
  State<DocumentTreeRow> createState() => _DocumentTreeRowState();
}

class _DocumentTreeRowState extends State<DocumentTreeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final active = widget.selected;
    final fg = active ? AppColors.ink : AppColors.inkMuted80;
    final indent = AppSpacing.sm + widget.depth * 16.0;

    final Color background;
    if (widget.dropHighlighted) {
      background = AppColors.primary.withValues(alpha: 0.12);
    } else if (active) {
      background = AppColors.canvas;
    } else if (_hover) {
      background = AppColors.canvas.withValues(alpha: 0.6);
    } else {
      background = Colors.transparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          color: background,
          padding: EdgeInsets.only(left: indent, right: AppSpacing.xs),
          child: Row(
            children: [
              // Chevron (folders only); reserves the same width otherwise so
              // icons line up across folders and documents.
              SizedBox(
                width: 18,
                child: doc.isFolder
                    ? GestureDetector(
                        onTap: widget.onToggle,
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          widget.expanded ? Icons.expand_more : Icons.chevron_right,
                          size: 16,
                          color: AppColors.inkMuted48,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Icon(
                doc.isFolder ? Icons.folder_outlined : Icons.description_outlined,
                size: 16,
                color: active ? AppColors.primary : AppColors.inkMuted48,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: widget.isRenaming
                    ? _RenameField(
                        controller: widget.renameController,
                        onSubmit: widget.onRenameSubmit,
                        onCancel: widget.onRenameCancel,
                      )
                    : Text(
                        doc.title.isEmpty ? 'Untitled' : doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: active
                            ? AppType.captionStrong(color: fg)
                            : AppType.caption(color: fg),
                      ),
              ),
              if ((_hover || active) && !widget.isRenaming)
                _RowMenu(isFolder: doc.isFolder, onSelected: widget.onMenu),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameField extends StatefulWidget {
  const _RenameField({
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final void Function(String title) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Select-all and focus once mounted so typing replaces the old title.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      style: AppType.caption(color: AppColors.ink),
      cursorColor: AppColors.primary,
      decoration: const InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      onSubmitted: widget.onSubmit,
      onTapOutside: (_) => widget.onSubmit(widget.controller.text),
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.isFolder, required this.onSelected});

  final bool isFolder;
  final void Function(DocMenuAction action) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DocMenuAction>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      iconSize: 16,
      icon: const Icon(Icons.more_horiz, color: AppColors.inkMuted48),
      onSelected: onSelected,
      itemBuilder: (context) => [
        if (isFolder) ...[
          const PopupMenuItem(
            value: DocMenuAction.newDocument,
            child: Text('New document'),
          ),
          const PopupMenuItem(
            value: DocMenuAction.newFolder,
            child: Text('New folder'),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(value: DocMenuAction.rename, child: Text('Rename')),
        const PopupMenuItem(value: DocMenuAction.delete, child: Text('Delete')),
      ],
    );
  }
}
