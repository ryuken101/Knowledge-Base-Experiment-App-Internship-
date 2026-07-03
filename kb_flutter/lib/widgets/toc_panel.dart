import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A heading parsed from the markdown source.
class TocEntry {
  const TocEntry({required this.level, required this.title, required this.line});

  /// 1–6, from the number of leading `#`.
  final int level;
  final String title;

  /// 0-based line index in the source, for best-effort scroll targeting.
  final int line;
}

/// Parse ATX headings (`#`..`######`) out of markdown source. Lines inside
/// fenced code blocks (``` ```) are skipped so `# comment` in code isn't picked up.
List<TocEntry> parseToc(String source) {
  final entries = <TocEntry>[];
  final heading = RegExp(r'^(#{1,6})\s+(.*)$');
  final lines = source.split('\n');
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final m = heading.firstMatch(line);
    if (m != null) {
      entries.add(TocEntry(
        level: m.group(1)!.length,
        title: m.group(2)!.trim(),
        line: i,
      ));
    }
  }
  return entries;
}

/// Left panel: the document outline on a parchment canvas, separated from the
/// editor by a single hairline. Tapping an entry calls [onTap] (best-effort
/// scroll).
class TocPanel extends StatelessWidget {
  const TocPanel({super.key, required this.entries, this.onTap});

  final List<TocEntry> entries;
  final void Function(TocEntry entry)? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.parchment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Text(
              'Outline',
              style: AppType.captionStrong(color: AppColors.inkMuted48),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                    child: Text(
                      'No headings yet.\nAdd "# Heading" lines to build the outline.',
                      style: AppType.caption(color: AppColors.inkMuted48),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      return _TocRow(entry: e, onTap: onTap);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TocRow extends StatefulWidget {
  const _TocRow({required this.entry, this.onTap});

  final TocEntry entry;
  final void Function(TocEntry entry)? onTap;

  @override
  State<_TocRow> createState() => _TocRowState();
}

class _TocRowState extends State<_TocRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final enabled = widget.onTap != null;
    final color = _hover ? AppColors.primary : AppColors.ink;
    final style = e.level == 1
        ? AppType.captionStrong(color: color)
        : AppType.caption(color: _hover ? AppColors.primary : AppColors.inkMuted80);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? () => widget.onTap!(e) : null,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg + (e.level - 1) * 14,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Text(
            e.title.isEmpty ? '(untitled)' : e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ),
    );
  }
}
