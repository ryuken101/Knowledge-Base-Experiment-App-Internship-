import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A single entry in the slash command menu. [apply] owns the insert/cursor
/// math so the screen just hands it the current value and takes the result.
class SlashCommand {
  const SlashCommand({
    required this.keyword,
    required this.label,
    required this.icon,
    required this.snippet,
    required this.cursorOffset,
  });

  /// The word typed after `/` that triggers this command (e.g. `h1`).
  final String keyword;

  /// Human label shown in the menu (e.g. `Heading 1`).
  final String label;

  /// Leading Material icon.
  final IconData icon;

  /// Markdown inserted in place of the `/keyword` token.
  final String snippet;

  /// Where the caret should land *within* [snippet] after insertion, measured
  /// from the snippet's start. Defaults handled by the const list below.
  final int cursorOffset;

  /// Replace the `[slashIndex, cursor)` range of [text] with [snippet] and
  /// return the new editing value with the caret placed at [cursorOffset]
  /// inside the inserted snippet.
  TextEditingValue apply(String text, int slashIndex, int cursor) {
    final newText = text.replaceRange(slashIndex, cursor, snippet);
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: slashIndex + cursorOffset),
    );
  }
}

/// The fixed command set. `cursorOffset` equals `snippet.length` for "end",
/// or points inside the snippet for templates (code block, bold, italic).
const List<SlashCommand> kSlashCommands = [
  SlashCommand(
    keyword: 'h1',
    label: 'Heading 1',
    icon: Icons.title,
    snippet: '# ',
    cursorOffset: 2,
  ),
  SlashCommand(
    keyword: 'h2',
    label: 'Heading 2',
    icon: Icons.title,
    snippet: '## ',
    cursorOffset: 3,
  ),
  SlashCommand(
    keyword: 'h3',
    label: 'Heading 3',
    icon: Icons.title,
    snippet: '### ',
    cursorOffset: 4,
  ),
  SlashCommand(
    keyword: 'code',
    label: 'Code Block',
    icon: Icons.code,
    snippet: '```\n\n```',
    cursorOffset: 4, // on the blank middle line
  ),
  SlashCommand(
    keyword: 'bullet',
    label: 'Bullet List',
    icon: Icons.format_list_bulleted,
    snippet: '- ',
    cursorOffset: 2,
  ),
  SlashCommand(
    keyword: 'numbered',
    label: 'Numbered List',
    icon: Icons.format_list_numbered,
    snippet: '1. ',
    cursorOffset: 3,
  ),
  SlashCommand(
    keyword: 'quote',
    label: 'Blockquote',
    icon: Icons.format_quote,
    snippet: '> ',
    cursorOffset: 2,
  ),
  SlashCommand(
    keyword: 'divider',
    label: 'Divider',
    icon: Icons.horizontal_rule,
    snippet: '---\n',
    cursorOffset: 4,
  ),
  SlashCommand(
    keyword: 'bold',
    label: 'Bold',
    icon: Icons.format_bold,
    snippet: '****',
    cursorOffset: 2, // between the stars
  ),
  SlashCommand(
    keyword: 'italic',
    label: 'Italic',
    icon: Icons.format_italic,
    snippet: '__',
    cursorOffset: 1, // between the underscores
  ),
];

/// Filter the command set by [query] (the text typed after `/`). An empty
/// query returns everything. Matches the query against both keyword and label,
/// case-insensitively, so `/list` surfaces both list types.
List<SlashCommand> filterSlashCommands(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kSlashCommands;
  return kSlashCommands
      .where((c) =>
          c.keyword.toLowerCase().contains(q) ||
          c.label.toLowerCase().contains(q))
      .toList();
}

/// Maximum rows shown before the list scrolls.
const int _kMaxVisibleRows = 6;
const double _kRowHeight = 40;
const double _kMenuWidth = 260;

/// The floating slash command menu. Driven entirely by the parent: it passes
/// the filtered [commands] and the [selectedIndex] (keyboard cursor), and gets
/// [onSelected] when a row is clicked.
class SlashMenu extends StatelessWidget {
  const SlashMenu({
    super.key,
    required this.commands,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<SlashCommand> commands;
  final int selectedIndex;
  final void Function(SlashCommand command) onSelected;

  /// Height the menu will occupy, so the parent can decide whether to flip it
  /// above the caret.
  static double heightFor(int count) {
    final rows = count.clamp(0, _kMaxVisibleRows);
    return rows * _kRowHeight + 2; // +2 for the hairline border
  }

  static double get width => _kMenuWidth;

  @override
  Widget build(BuildContext context) {
    final visibleRows = commands.length.clamp(1, _kMaxVisibleRows);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: _kMenuWidth,
        height: visibleRows * _kRowHeight + 2,
        decoration: BoxDecoration(
          color: AppColors.parchment,
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: commands.length,
          itemExtent: _kRowHeight,
          itemBuilder: (context, i) => _SlashRow(
            command: commands[i],
            selected: i == selectedIndex,
            onTap: () => onSelected(commands[i]),
          ),
        ),
      ),
    );
  }
}

class _SlashRow extends StatefulWidget {
  const _SlashRow({
    required this.command,
    required this.selected,
    required this.onTap,
  });

  final SlashCommand command;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SlashRow> createState() => _SlashRowState();
}

class _SlashRowState extends State<_SlashRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hover;
    final fg = active ? AppColors.ink : AppColors.inkMuted80;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: active ? AppColors.canvas : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Icon(widget.command.icon, size: 16, color: AppColors.inkMuted48),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.command.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body(color: fg),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '/${widget.command.keyword}',
                style: AppType.caption(color: AppColors.inkMuted48),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
