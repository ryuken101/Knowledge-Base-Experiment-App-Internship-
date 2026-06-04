import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/knowledge_base.dart';
import '../providers/kb_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import '../widgets/slash_menu.dart';
import '../widgets/toc_panel.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _controller = TextEditingController();
  final _editorScroll = ScrollController();
  final _previewScroll = ScrollController();

  /// Last content known to be persisted on the server; the editor is "dirty"
  /// when it diverges from this.
  String _savedContent = '';

  /// True while a save/clear/delete request is in flight.
  bool _mutating = false;

  // ---- Slash command menu ----
  // Anchors the floating menu to the editor field; the portal owns its overlay
  // lifecycle so there is nothing to dispose.
  final LayerLink _editorLink = LayerLink();
  final GlobalKey _editorFieldKey = GlobalKey();
  final OverlayPortalController _slashPortal = OverlayPortalController();

  /// Index of the `/` that opened the menu (-1 when closed), the current
  /// filtered command list, and the keyboard-highlighted row.
  int _slashIndex = -1;
  List<SlashCommand> _slashFiltered = const [];
  int _slashSelected = 0;

  @override
  void initState() {
    super.initState();
    // Rebuild preview, outline and the dirty indicator as the user types, and
    // re-evaluate the slash trigger.
    _controller.addListener(_onEditorChanged);
  }

  void _onEditorChanged() {
    setState(() {});
    _updateSlashState();
  }

  /// Recompute whether a slash command menu should be open, based on the text
  /// immediately before the (collapsed) caret. Triggers only when `/` sits at
  /// line start or after whitespace, with a single non-whitespace token after
  /// it — so URLs like `http://` never open the menu.
  void _updateSlashState() {
    final value = _controller.value;
    final sel = value.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _closeSlashMenu();
      return;
    }
    final cursor = sel.baseOffset;
    final text = value.text;

    // Walk back from the caret to the nearest `/`, bailing on whitespace.
    var i = cursor - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == '/') break;
      if (ch == ' ' || ch == '\n' || ch == '\t') {
        i = -1;
        break;
      }
      i--;
    }
    if (i < 0) {
      _closeSlashMenu();
      return;
    }
    // The `/` must start a token: at line start or preceded by whitespace.
    if (i > 0) {
      final prev = text[i - 1];
      if (prev != ' ' && prev != '\n' && prev != '\t') {
        _closeSlashMenu();
        return;
      }
    }

    final query = text.substring(i + 1, cursor);
    final filtered = filterSlashCommands(query);
    if (filtered.isEmpty) {
      _closeSlashMenu();
      return;
    }

    final wasOpen = _slashPortal.isShowing;
    _slashIndex = i;
    _slashFiltered = filtered;
    _slashSelected = wasOpen ? _slashSelected.clamp(0, filtered.length - 1) : 0;
    if (!wasOpen) _slashPortal.show();
  }

  void _closeSlashMenu() {
    if (_slashPortal.isShowing) _slashPortal.hide();
    _slashIndex = -1;
    _slashFiltered = const [];
    _slashSelected = 0;
  }

  /// Replace the `/query` token with the command's snippet and dismiss. Only
  /// touches the editor text, so dirty-tracking and Save work unchanged.
  void _applySlashCommand(SlashCommand command) {
    if (_slashIndex < 0) return;
    final cursor = _controller.selection.baseOffset;
    if (cursor < _slashIndex) {
      _closeSlashMenu();
      return;
    }
    _controller.value = command.apply(_controller.text, _slashIndex, cursor);
    _closeSlashMenu();
  }

  /// While the menu is open, intercept navigation keys before the TextField
  /// acts on them; otherwise let everything through untouched.
  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (!_slashPortal.isShowing) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _slashSelected =
          (_slashSelected + 1).clamp(0, _slashFiltered.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _slashSelected =
          (_slashSelected - 1).clamp(0, _slashFiltered.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_slashFiltered.isNotEmpty) {
        _applySlashCommand(_slashFiltered[_slashSelected]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(_closeSlashMenu);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Where to place the menu (field-local), anchored just below the `/`. Uses a
  /// TextPainter replica of the editor to find the caret pixel, accounts for the
  /// field's internal scroll, and flips above the caret near the screen bottom.
  Offset _slashMenuOffset() {
    final box =
        _editorFieldKey.currentContext?.findRenderObject() as RenderBox?;
    final style = AppType.mono(color: AppColors.ink);
    final lineHeight = (style.fontSize ?? 14) * (style.height ?? 1.0);
    final width = box?.size.width ?? SlashMenu.width;

    final text = _controller.text;
    final clampedIndex = _slashIndex.clamp(0, text.length);
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(text: text.substring(0, clampedIndex), style: style),
    )..layout(maxWidth: width);
    final caret =
        painter.getOffsetForCaret(TextPosition(offset: clampedIndex), Rect.zero);

    final caretViewportDy = caret.dy - _editorScroll.offset;
    final maxLeft = (width - SlashMenu.width).clamp(0.0, double.infinity);
    final left = caret.dx.clamp(0.0, maxLeft);

    final menuHeight = SlashMenu.heightFor(_slashFiltered.length);
    var top = caretViewportDy + lineHeight;
    if (box != null) {
      final globalTop = box.localToGlobal(Offset(0, top));
      final screenHeight = MediaQuery.of(context).size.height;
      if (globalTop.dy + menuHeight > screenHeight - 12) {
        top = caretViewportDy - menuHeight - 4; // flip above the caret
      }
    }
    return Offset(left, top);
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorScroll.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  bool get _dirty => _controller.text != _savedContent;

  /// Adopt server content as the new baseline and reset the editor to it.
  void _adoptServerContent(String content) {
    _savedContent = content;
    if (_controller.text != content) {
      _controller.text = content;
    }
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

  Future<void> _save() =>
      _runMutation(() => ref.read(kbProvider.notifier).save(_controller.text));

  Future<void> _clear() =>
      _runMutation(() => ref.read(kbProvider.notifier).clear());

  Future<void> _deleteFile() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete knowledge base file?'),
            content: const Text(
              'This removes the entire file. A fresh empty one is created the '
              'next time it loads.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              PillButton(
                label: 'Delete',
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;
    if (ok) {
      await _runMutation(() => ref.read(kbProvider.notifier).deleteFile());
    }
  }

  void _jumpToHeading(TocEntry entry) {
    // Best-effort: scroll both panes proportionally to the heading's line.
    final totalLines = '\n'.allMatches(_controller.text).length + 1;
    final fraction = totalLines <= 1 ? 0.0 : entry.line / totalLines;
    for (final c in [_editorScroll, _previewScroll]) {
      if (c.hasClients) {
        c.animateTo(
          fraction * c.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kbProvider);

    // React to authoritative server updates (load / save / clear / delete) by
    // re-seeding the editor to the new baseline.
    ref.listen<AsyncValue<KnowledgeBase>>(kbProvider, (prev, next) {
      next.whenOrNull(
        data: (kb) {
          if (kb.content != _savedContent) {
            setState(() => _adoptServerContent(kb.content));
          }
        },
      );
    });

    final busy = state.isLoading || _mutating;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: const Text('Knowledge Base'),
        actions: [
          if (_dirty) const _UnsavedBadge(),
          PillButton(
            label: 'Save',
            icon: Icons.save_outlined,
            onPressed: (busy || !_dirty) ? null : _save,
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: busy ? null : _clear,
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: busy ? null : _deleteFile,
            child: const Text('Delete'),
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
      body: state.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, _) => _ErrorView(
          message: '$err',
          onRetry: () => ref.invalidate(kbProvider),
        ),
        data: (_) => _buildEditor(context),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: outline.
        SizedBox(
          width: 248,
          child: TocPanel(
            entries: parseToc(_controller.text),
            onTap: _jumpToHeading,
          ),
        ),
        const VerticalDivider(width: 1),
        // Right: editor + live preview, side by side.
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Pane(
                  label: 'Markdown',
                  background: AppColors.canvas,
                  child: Focus(
                    canRequestFocus: false,
                    onKeyEvent: _handleEditorKey,
                    child: OverlayPortal(
                      controller: _slashPortal,
                      overlayChildBuilder: (context) =>
                          CompositedTransformFollower(
                        link: _editorLink,
                        showWhenUnlinked: false,
                        offset: _slashMenuOffset(),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: SlashMenu(
                            commands: _slashFiltered,
                            selectedIndex: _slashSelected,
                            onSelected: _applySlashCommand,
                          ),
                        ),
                      ),
                      child: CompositedTransformTarget(
                        key: _editorFieldKey,
                        link: _editorLink,
                        child: TextField(
                          controller: _controller,
                          scrollController: _editorScroll,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          cursorColor: AppColors.primary,
                          style: AppType.mono(color: AppColors.ink),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: '# Write markdown here…  (type / for commands)',
                            hintStyle: AppType.mono(color: AppColors.inkMuted48),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _Pane(
                  label: 'Preview',
                  background: AppColors.pearl,
                  padded: false,
                  child: Markdown(
                    controller: _previewScroll,
                    data: _controller.text.isEmpty
                        ? '_Nothing to preview yet._'
                        : _controller.text,
                    selectable: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                    styleSheet: buildMarkdownStyle(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
