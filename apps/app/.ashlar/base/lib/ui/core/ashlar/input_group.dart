// Ashlar UI: Input Group. Copied into your app by `ashlar add input-group`; it is yours to
// change.

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A text field and the things that belong with it inside one border: text before it
/// ("https://"), a button after it, a toolbar under a text area. Give it an Input or a
/// Textarea with `decorated: false`; the group draws the border, the fill and the focus
/// ring round them all.
///
/// ```dart
/// InputGroup(
///   start: Text('https://'),
///   end: Text('.com'),
///   child: Input(decorated: false, placeholder: 'example'),
/// )
/// InputGroup(
///   bottom: Row(children: [Text('120 characters left'), Spacer(), Button(size: ButtonSize.sm, onPressed: send, child: Text('Send'))]),
///   child: Textarea(decorated: false, placeholder: 'Write a reply'),
/// )
/// ```
class InputGroup extends StatefulWidget {
  const InputGroup({
    super.key,
    required this.child,
    this.start,
    this.end,
    this.top,
    this.bottom,
    this.error = false,
  });

  /// The field: an Input with its decoration off, or a Textarea.
  final Widget child;

  /// Before the field and after it, on its line.
  final Widget? start, end;

  /// Above the field and under it, across the whole width.
  final Widget? top, bottom;

  /// Draws the group as invalid.
  final bool error;

  @override
  State<InputGroup> createState() => _InputGroupState();
}

class _InputGroupState extends State<InputGroup> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    Widget addon(Widget w, EdgeInsetsGeometry padding) => Padding(
      padding: padding,
      child: DefaultTextStyle.merge(
        style: t.text.sm.copyWith(color: c.mutedForeground),
        child: IconTheme.merge(
          data: IconThemeData(color: c.mutedForeground, size: 16),
          child: w,
        ),
      ),
    );
    final ring = widget.error ? c.destructive : c.ring;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // The ring shows while the field, or anything in the group, has focus.
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: t.duration,
        decoration: BoxDecoration(
          color: t.brightness == Brightness.dark
              ? Color.alphaBlend(
                  c.input.withValues(alpha: c.input.a * .3),
                  c.background,
                )
              : c.background,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: Border.all(
            color: widget.error ? c.destructive : (_focused ? c.ring : c.input),
          ),
          boxShadow: [
            if (_focused)
              BoxShadow(
                color: ring.withValues(alpha: widget.error ? .2 : .5),
                spreadRadius: 3,
              ),
            ...t.shadowXs,
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.top != null)
              addon(widget.top!, const EdgeInsets.fromLTRB(12, 10, 12, 0)),
            Row(
              children: [
                if (widget.start != null)
                  addon(
                    widget.start!,
                    const EdgeInsetsDirectional.only(start: 12, end: 2),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: widget.start == null ? 12 : 4,
                      end: widget.end == null ? 12 : 4,
                    ),
                    child: widget.child,
                  ),
                ),
                if (widget.end != null)
                  addon(
                    widget.end!,
                    const EdgeInsetsDirectional.only(start: 2, end: 8),
                  ),
              ],
            ),
            if (widget.bottom != null)
              addon(
                widget.bottom!,
                const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 8),
              ),
          ],
        ),
      ),
    );
  }
}
