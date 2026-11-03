// Ashlar UI: Textarea. Copied into your app by `ashlar add textarea`; it is yours to change.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'input.dart';
import 'theme.dart';

/// A text field for more than one line. It starts [minLines] tall and grows to [maxLines]
/// as the text does, then scrolls. With [resizable], a grip at the bottom right drags it
/// taller or shorter, a line at a time; the text then scrolls inside the height chosen.
///
/// ```dart
/// Textarea(placeholder: 'Tell us what happened', onChanged: (v) => note = v)
/// ```
class Textarea extends StatefulWidget {
  const Textarea({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.enabled = true,
    this.readOnly = false,
    this.error = false,
    this.autofocus = false,
    this.minLines = 3,
    this.maxLines = 8,
    this.resizable = true,
    this.inputFormatters,
    this.onChanged,
    this.semanticLabel,
    this.decorated = true,
  });

  /// Its text, to read and set from outside; one is made when not given.
  final TextEditingController? controller;

  /// Its focus node, to move focus to it or follow it from outside; one is made when not
  /// given.
  final FocusNode? focusNode;

  /// Faint text shown while it is empty.
  final String? placeholder;

  /// False fades it and stops it taking focus or typing.
  final bool enabled;

  /// Shows its text, selectable, but takes no typing.
  final bool readOnly;

  /// Marks it as wrong, in the destructive colour. Inside a FormItem, a screen reader
  /// also hears that it is invalid.
  final bool error;

  /// Takes the keyboard's focus when it first appears.
  final bool autofocus;

  /// The fewest lines it shows, even when empty.
  final int minLines;

  /// The most lines it grows to before scrolling.
  final int maxLines;

  /// Shows the grip that drags it taller or shorter.
  final bool resizable;

  /// Rules for what can be typed, such as digits only.
  final List<TextInputFormatter>? inputFormatters;

  /// Told the text as it changes.
  final ValueChanged<String>? onChanged;

  /// What a screen reader calls it when its visible text does not say, as for an icon
  /// alone.
  final String? semanticLabel;

  /// False draws the bare text, for an InputGroup.
  final bool decorated;

  @override
  State<Textarea> createState() => _TextareaState();
}

class _TextareaState extends State<Textarea> {
  /// The height dragged to, in lines; null until the grip is used.
  int? _lines;
  double _dragged = 0;
  final _box = GlobalKey();

  static const _fewest = 2;

  void _start(DragStartDetails _) =>
      _dragged = _box.currentContext?.size?.height ?? 0;

  void _drag(DragUpdateDetails d, double lineHeight, double chrome) {
    _dragged += d.delta.dy;
    final lines = ((_dragged - chrome) / lineHeight).round().clamp(_fewest, 50);
    if (lines != _lines) setState(() => _lines = lines);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final lines = _lines;
    final field = Input(
      key: _box,
      controller: widget.controller,
      focusNode: widget.focusNode,
      placeholder: widget.placeholder,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      error: widget.error,
      autofocus: widget.autofocus,
      minLines: lines ?? widget.minLines,
      maxLines: lines ?? widget.maxLines,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      semanticLabel: widget.semanticLabel,
      decorated: widget.decorated,
    );
    if (!widget.resizable || !widget.enabled) return field;
    final style = t.text.sm;
    final lineHeight = style.fontSize! * (style.height ?? 1.2);
    // Padding and border round the text: 8 above and below, and a pixel of border each side.
    final chrome = widget.decorated ? 18.0 : 16.0;
    return Stack(
      children: [
        field,
        PositionedDirectional(
          end: 2,
          bottom: 2,
          // A mouse and touch handle, as in a browser; the text itself needs no keyboard way.
          child: ExcludeSemantics(
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _start,
                onVerticalDragUpdate: (d) => _drag(d, lineHeight, chrome),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CustomPaint(
                    painter: _Grip(c.mutedForeground.withValues(alpha: .6)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two short diagonal strokes in the corner.
class _Grip extends CustomPainter {
  _Grip(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    canvas.drawLine(Offset(w - 3, h - 9), Offset(w - 9, h - 3), p);
    canvas.drawLine(Offset(w - 3, h - 5.5), Offset(w - 5.5, h - 3), p);
  }

  @override
  bool shouldRepaint(_Grip old) => old.color != color;
}
