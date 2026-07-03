import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The signature Apple pill CTA. Two grammars:
/// - primary: filled Action Blue, white label.
/// - ghost: transparent with an Action Blue hairline border + blue label.
///
/// Press applies the system-wide `scale(0.95)` micro-interaction. Disabled
/// (null [onPressed]) renders muted with no press response.
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.primary = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    final Color bg;
    final Color fg;
    final BoxBorder? border;
    if (widget.primary) {
      bg = enabled ? AppColors.primary : AppColors.parchment;
      fg = enabled ? AppColors.canvas : AppColors.inkMuted48;
      border = null;
    } else {
      bg = Colors.transparent;
      fg = enabled ? AppColors.primary : AppColors.inkMuted48;
      border = Border.all(
        color: enabled ? AppColors.primary : AppColors.hairline,
      );
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: bg,
              border: border,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 16, color: fg),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(widget.label, style: AppType.body(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
