import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/knowledge_base.dart';
import '../providers/kb_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
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

  @override
  void initState() {
    super.initState();
    // Rebuild preview, outline and the dirty indicator as the user types.
    _controller.addListener(() => setState(() {}));
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
                      hintText: '# Write markdown here…',
                      hintStyle: AppType.mono(color: AppColors.inkMuted48),
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
