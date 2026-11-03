// Ashlar UI: Reasoning. Copied into your app by `ashlar add reasoning`; it is yours to change.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import 'collapsible.dart';
import 'pressable.dart';
import 'shimmer.dart';
import 'theme.dart';

/// What a model thought before it answered, folded away under a line that says so. While
/// [thinking] the line shimmers ("Thinking…") and the thoughts show as they arrive; when it
/// is done the line says how long it took ("Thought for 12 seconds") and the thoughts fold
/// away, a tap from being read again.
///
/// ```dart
/// Reasoning(
///   thinking: !done,
///   took: done ? elapsed : null,
///   child: Markdown(thoughts, streaming: !done),
/// )
/// ```
class Reasoning extends StatefulWidget {
  const Reasoning({
    super.key,
    required this.child,
    this.thinking = false,
    this.took,
    this.label,
    this.closeWhenDone = true,
  });

  /// The thoughts: Text, or Markdown for formatted ones.
  final Widget child;

  /// Still thinking: the line shimmers and the thoughts are open.
  final bool thinking;

  /// How long it thought, said on the line once it is done.
  final Duration? took;

  /// The line's words, in place of "Thinking…" and "Thought for …".
  final String? label;

  /// Folds the thoughts away when [thinking] ends, unless the person opened or closed
  /// them meanwhile.
  final bool closeWhenDone;

  @override
  State<Reasoning> createState() => _ReasoningState();
}

/// "12 seconds", "1 minute", "2 minutes".
String _spoken(Duration d) {
  final s = (d.inMilliseconds / 1000).round();
  if (s < 60) return s == 1 ? '1 second' : '$s seconds';
  final m = (s / 60).round();
  return m == 1 ? '1 minute' : '$m minutes';
}

class _ReasoningState extends State<Reasoning> {
  late bool _open = widget.thinking;

  /// The person opened or closed it themselves: it stays as they left it.
  bool _chosen = false;

  @override
  void didUpdateWidget(Reasoning old) {
    super.didUpdateWidget(old);
    if (old.thinking && !widget.thinking && widget.closeWhenDone && !_chosen) {
      _open = false;
    } else if (!old.thinking && widget.thinking && !_chosen) {
      _open = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final words =
        widget.label ??
        (widget.thinking
            ? 'Thinking…'
            : widget.took == null
            ? 'Thoughts'
            : 'Thought for ${_spoken(widget.took!)}');
    return Collapsible(
      open: _open,
      onChanged: (open) => setState(() {
        _open = open;
        _chosen = true;
      }),
      builder: (context, open, toggle) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Pressable(
          onPressed: toggle,
          expanded: open,
          semanticLabel: words,
          builder: (context, state) {
            final ink = state.hovered || state.focused
                ? c.foreground
                : c.mutedForeground;
            final text = Text(words, style: t.text.sm.copyWith(color: ink));
            return AnimatedContainer(
              duration: t.duration,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.radiusSm),
                border: Border.all(
                  color: state.focused ? c.ring : c.ring.withValues(alpha: 0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AshlarIcon(
                    AshlarIconsRoundedStroke.brain,
                    size: 16,
                    color: ink,
                  ),
                  const SizedBox(width: 6),
                  if (widget.thinking) Shimmer(child: text) else text,
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: open ? 0 : -.25,
                    duration: t.duration,
                    child: AshlarIcon(
                      AshlarIconsRoundedStroke.chevronDown,
                      size: 16,
                      color: ink,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      child: Container(
        margin: const EdgeInsetsDirectional.only(start: 9, top: 6),
        padding: const EdgeInsetsDirectional.only(start: 14),
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(color: c.border, width: 2),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: t.text.sm.copyWith(color: c.mutedForeground),
          child: widget.child,
        ),
      ),
    );
  }
}
