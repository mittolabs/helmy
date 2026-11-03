// Ashlar UI: Tooltip. Copied into your app by `ashlar add tooltip`; it is yours to change.
//
// Built on RawTooltip from Flutter's widgets layer, which shows it on hover and on a long
// press. This file also shows it on keyboard focus and gives screen readers the message.

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A short label that appears over [child] when it is hovered, focused from the keyboard
/// or long pressed. Use it for what an icon button does, not for anything a person needs.
///
/// ```dart
/// Tooltip(message: 'Add to library', child: Button(size: ButtonSize.icon, semanticLabel: 'Add', onPressed: add, child: AshlarIcon(AshlarIconsRoundedStroke.plus)))
/// ```
/// The side of its child a [Tooltip] shows on.
enum TooltipSide { top, bottom, left, right }

class Tooltip extends StatefulWidget {
  const Tooltip({
    super.key,
    required this.message,
    required this.child,
    this.side = TooltipSide.top,
    this.content,
  });

  /// What it says, and what a screen reader hears.
  final String message;

  /// What it describes: hovered, focused or long pressed to show it.
  final Widget child;

  /// Which side of the child it shows on. It flips when there is no room.
  final TooltipSide side;

  /// Shown in place of [message] when there is more to show: a shortcut in Kbd keys.
  final Widget? content;

  @override
  State<Tooltip> createState() => _TooltipState();
}

class _TooltipState extends State<Tooltip> {
  final _tip = GlobalKey<RawTooltipState>();

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) {
          RawTooltip.dismissAllToolTips();
        } else if (FocusManager.instance.highlightMode ==
            FocusHighlightMode.traditional) {
          _tip.currentState?.ensureTooltipVisible();
        }
      },
      child: RawTooltip(
        key: _tip,
        // The message goes on the control itself, so a screen reader hears it with the
        // control's name rather than as a separate item.
        semanticsTooltip: null,
        hoverDelay: Duration.zero,
        positionDelegate: (p) {
          const gap = 4.0, margin = 8.0;
          final t = p.target,
              ts = p.targetSize,
              size = p.tooltipSize,
              room = p.overlaySize;
          double clampX(double x) => x.clamp(
            margin,
            (room.width - size.width - margin).clamp(margin, double.infinity),
          );
          double clampY(double y) => y.clamp(
            margin,
            (room.height - size.height - margin).clamp(margin, double.infinity),
          );
          final above = t.dy - ts.height / 2 - gap - size.height,
              under = t.dy + ts.height / 2 + gap;
          final before = t.dx - ts.width / 2 - gap - size.width,
              after = t.dx + ts.width / 2 + gap;
          final fitsAbove = above >= margin,
              fitsUnder = under + size.height <= room.height - margin;
          final fitsBefore = before >= margin,
              fitsAfter = after + size.width <= room.width - margin;
          switch (widget.side) {
            case TooltipSide.top || TooltipSide.bottom:
              final down = widget.side == TooltipSide.bottom
                  ? (fitsUnder || !fitsAbove)
                  : !(fitsAbove || !fitsUnder);
              return Offset(
                clampX(t.dx - size.width / 2),
                down ? under : above,
              );
            case TooltipSide.left || TooltipSide.right:
              final right = widget.side == TooltipSide.right
                  ? (fitsAfter || !fitsBefore)
                  : !(fitsBefore || !fitsAfter);
              return Offset(
                right ? after : before,
                clampY(t.dy - size.height / 2),
              );
          }
        },
        tooltipBuilder: (context, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: .95, end: 1.0).animate(animation),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(t.radiusMd),
              ),
              child: DefaultTextStyle.merge(
                style: t.text.xs.copyWith(color: c.primaryForeground),
                child: IconTheme.merge(
                  data: IconThemeData(color: c.primaryForeground, size: 12),
                  child: widget.content ?? Text(widget.message),
                ),
              ),
            ),
          ),
        ),
        child: MergeSemantics(
          child: Semantics(tooltip: widget.message, child: widget.child),
        ),
      ),
    );
  }
}
