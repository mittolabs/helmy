// Ashlar UI: Color Picker. Copied into your app by `ashlar add color-picker`; it is yours to
// change.
//
// Any colour, chosen by hand: a square for how strong and how light, a strip for the hue,
// a strip for how see-through if you like, the hex to type, and swatches to start from.
// Each part takes the arrow keys and tells a screen reader where it is.
//
// The square and the strips are drawn in the colours being chosen (white, black, every
// hue), not the theme's: they are the colour space, not the page.

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'input.dart';
import 'popover.dart';
import 'pressable.dart';
import 'theme.dart';

/// [color] as hex: RRGGBB, or AARRGGBB when [alpha] and it is not opaque.
String colorHex(Color color, {bool alpha = false}) {
  String two(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  final rgb = '${two(color.r)}${two(color.g)}${two(color.b)}'.toUpperCase();
  return alpha && color.a < 1 ? '${two(color.a).toUpperCase()}$rgb' : rgb;
}

/// The colour [text] spells in hex (RGB, RRGGBB or AARRGGBB, a # or not); null if it
/// spells none.
Color? parseColorHex(String text) {
  var h = text.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) return null;
  return Color(int.parse(h, radix: 16));
}

/// A colour picker: a square for saturation and brightness, a hue strip, an opacity strip
/// with [alpha], a hex field, and [swatches] to start from.
///
/// ```dart
/// ColorPicker(value: brand, onChanged: (c) => setState(() => brand = c))
/// ```
class ColorPicker extends StatefulWidget {
  const ColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.alpha = false,
    this.swatches,
    this.width = 240,
    this.semanticLabel = 'Colour',
  });

  final Color value;
  final ValueChanged<Color> onChanged;

  /// An opacity strip, and eight digits of hex.
  final bool alpha;

  /// Colours to pick at a tap, under the rest.
  final List<Color>? swatches;
  final double width;

  /// What a screen reader calls the picker.
  final String semanticLabel;

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  // Kept apart from the colour, so the hue holds while the colour is grey.
  late HSVColor _hsv = HSVColor.fromColor(widget.value);
  late final _hex = TextEditingController(
    text: colorHex(widget.value, alpha: widget.alpha),
  );
  final _hexFocus = FocusNode();

  @override
  void didUpdateWidget(ColorPicker old) {
    super.didUpdateWidget(old);
    if (widget.value != _hsv.toColor()) {
      final next = HSVColor.fromColor(widget.value);
      // A grey from outside keeps the hue the strip was at.
      _hsv = next.saturation == 0 ? next.withHue(_hsv.hue) : next;
      if (!_hexFocus.hasFocus) {
        _hex.text = colorHex(widget.value, alpha: widget.alpha);
      }
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    final c = hsv.toColor();
    if (!_hexFocus.hasFocus) _hex.text = colorHex(c, alpha: widget.alpha);
    widget.onChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final hue = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    String percent(double v) => '${(v * 100).round()}%';
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      value: '#${colorHex(_hsv.toColor(), alpha: widget.alpha)}',
      child: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Plane(
              hsv: _hsv,
              hue: hue,
              label: 'Saturation and brightness',
              describe: (sat, val) =>
                  'saturation ${percent(sat)}, brightness ${percent(val)}',
              onChanged: _set,
            ),
            const SizedBox(height: 12),
            _Strip(
              label: 'Hue',
              value: _hsv.hue / 360,
              describe: (v) => '${(v * 360).round()} degrees',
              step: 1 / 360,
              paint: (canvas, rect) {
                canvas.drawRect(
                  rect,
                  Paint()
                    ..shader = LinearGradient(
                      colors: [
                        for (var h = 0; h <= 360; h += 60)
                          HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                      ],
                    ).createShader(rect),
                );
              },
              thumb: hue,
              onChanged: (v) => _set(_hsv.withHue((v * 360).clamp(0, 359.99))),
            ),
            if (widget.alpha) ...[
              const SizedBox(height: 10),
              _Strip(
                label: 'Opacity',
                value: _hsv.alpha,
                describe: percent,
                step: .01,
                paint: (canvas, rect) {
                  // A check, so what is see-through shows as such.
                  const cell = 6.0;
                  final light = Paint()..color = c.background;
                  final dark = Paint()..color = c.muted;
                  for (var x = rect.left; x < rect.right; x += cell) {
                    for (var y = rect.top; y < rect.bottom; y += cell) {
                      final odd =
                          (((x - rect.left) / cell).floor() +
                                  ((y - rect.top) / cell).floor())
                              .isOdd;
                      canvas.drawRect(
                        Rect.fromLTWH(
                          x,
                          y,
                          math.min(cell, rect.right - x),
                          math.min(cell, rect.bottom - y),
                        ),
                        odd ? dark : light,
                      );
                    }
                  }
                  final solid = _hsv.withAlpha(1).toColor();
                  canvas.drawRect(
                    rect,
                    Paint()
                      ..shader = LinearGradient(
                        colors: [solid.withValues(alpha: 0), solid],
                      ).createShader(rect),
                  );
                },
                thumb: _hsv.toColor(),
                onChanged: (v) => _set(_hsv.withAlpha(v.clamp(0, 1))),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _hsv.toColor(),
                    borderRadius: BorderRadius.circular(t.radiusMd),
                    border: Border.all(color: c.border),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Input(
                    controller: _hex,
                    focusNode: _hexFocus,
                    semanticLabel: 'Hex',
                    leading: Text(
                      '#',
                      style: t.text.sm.copyWith(color: c.mutedForeground),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                      LengthLimitingTextInputFormatter(widget.alpha ? 9 : 7),
                    ],
                    onChanged: (s) {
                      final parsed = parseColorHex(s);
                      if (parsed == null) return;
                      final next = HSVColor.fromColor(
                        widget.alpha ? parsed : parsed.withValues(alpha: 1),
                      );
                      setState(
                        () => _hsv = next.saturation == 0
                            ? next.withHue(_hsv.hue)
                            : next,
                      );
                      widget.onChanged(next.toColor());
                    },
                    onSubmitted: (_) => _hex.text = colorHex(
                      _hsv.toColor(),
                      alpha: widget.alpha,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.swatches case final swatches?
                when swatches.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in swatches)
                    Pressable(
                      onPressed: () {
                        final next = HSVColor.fromColor(s);
                        _set(
                          next.saturation == 0 ? next.withHue(_hsv.hue) : next,
                        );
                      },
                      semanticLabel: '#${colorHex(s, alpha: widget.alpha)}',
                      selected: s == _hsv.toColor(),
                      builder: (context, state) => Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: s,
                          borderRadius: BorderRadius.circular(t.radiusSm),
                          border: Border.all(
                            color: state.focused || s == _hsv.toColor()
                                ? c.ring
                                : c.border,
                            width: state.focused || s == _hsv.toColor() ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.dx, this.dy);

  final double dx, dy;
}

/// The square: saturation along it, brightness up it.
class _Plane extends StatefulWidget {
  const _Plane({
    required this.hsv,
    required this.hue,
    required this.label,
    required this.describe,
    required this.onChanged,
  });

  final HSVColor hsv;
  final Color hue;
  final String label;

  /// Saturation and brightness as a screen reader hears them.
  final String Function(double saturation, double brightness) describe;
  final ValueChanged<HSVColor> onChanged;

  @override
  State<_Plane> createState() => _PlaneState();
}

class _PlaneState extends State<_Plane> {
  bool _focused = false;

  void _at(Offset p, Size size) => widget.onChanged(
    widget.hsv
        .withSaturation((p.dx / size.width).clamp(0, 1))
        .withValue((1 - p.dy / size.height).clamp(0, 1)),
  );

  void _move(double dx, double dy) => widget.onChanged(
    widget.hsv
        .withSaturation((widget.hsv.saturation + dx).clamp(0, 1))
        .withValue((widget.hsv.value + dy).clamp(0, 1)),
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    const step = .01, big = .1;
    return Semantics(
      slider: true,
      label: widget.label,
      value: widget.describe(widget.hsv.saturation, widget.hsv.value),
      increasedValue: widget.describe(
        widget.hsv.saturation,
        (widget.hsv.value + step).clamp(0, 1),
      ),
      decreasedValue: widget.describe(
        widget.hsv.saturation,
        (widget.hsv.value - step).clamp(0, 1),
      ),
      onIncrease: () => _move(0, step),
      onDecrease: () => _move(0, -step),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.precise,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowRight): _MoveIntent(step, 0),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveIntent(-step, 0),
          SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(0, step),
          SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(0, -step),
          SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
              _MoveIntent(big, 0),
          SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
              _MoveIntent(-big, 0),
          SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): _MoveIntent(
            0,
            big,
          ),
          SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
              _MoveIntent(0, -big),
        },
        actions: {
          _MoveIntent: CallbackAction<_MoveIntent>(
            onInvoke: (i) => _move(i.dx, i.dy),
          ),
        },
        child: LayoutBuilder(
          builder: (context, box) {
            final size = Size(box.maxWidth, box.maxWidth * .66);
            return GestureDetector(
              onPanDown: (d) => _at(d.localPosition, size),
              onPanUpdate: (d) => _at(d.localPosition, size),
              child: SizedBox.fromSize(
                size: size,
                child: CustomPaint(
                  painter: _PlanePainter(
                    hsv: widget.hsv,
                    hue: widget.hue,
                    radius: t.radiusMd,
                    ring: _focused ? c.ring : null,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlanePainter extends CustomPainter {
  _PlanePainter({
    required this.hsv,
    required this.hue,
    required this.radius,
    this.ring,
  });

  final HSVColor hsv;
  final Color hue;
  final double radius;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(shape);
    // White to the hue along it, then clear to black down it.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [const Color(0xFFFFFFFF), hue])
            .createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
    canvas.restore();
    final at = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      at,
      7,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      at,
      8.5,
      Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (ring != null) {
      canvas.drawRRect(
        shape.inflate(2),
        Paint()
          ..color = ring!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_PlanePainter old) =>
      old.hsv != hsv || old.ring != ring || old.radius != radius;
}

/// A strip with a thumb: the hue, or the opacity.
class _Strip extends StatefulWidget {
  const _Strip({
    required this.label,
    required this.value,
    required this.describe,
    required this.step,
    required this.paint,
    required this.thumb,
    required this.onChanged,
  });

  final String label;

  /// Where the thumb is, 0 to 1.
  final double value;

  /// A value as a screen reader hears it.
  final String Function(double value) describe;
  final double step;
  final void Function(Canvas canvas, Rect rect) paint;
  final Color thumb;
  final ValueChanged<double> onChanged;

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final s = widget.step;
    void move(double by) => widget.onChanged((widget.value + by).clamp(0, 1));
    return Semantics(
      slider: true,
      label: widget.label,
      value: widget.describe(widget.value),
      increasedValue: widget.describe((widget.value + s).clamp(0, 1)),
      decreasedValue: widget.describe((widget.value - s).clamp(0, 1)),
      onIncrease: () => move(s),
      onDecrease: () => move(-s),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): _MoveIntent(
            s,
            0,
          ),
          const SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(s, 0),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveIntent(
            -s,
            0,
          ),
          const SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(
            -s,
            0,
          ),
          const SingleActivator(LogicalKeyboardKey.pageUp): _MoveIntent(
            s * 10,
            0,
          ),
          const SingleActivator(LogicalKeyboardKey.pageDown): _MoveIntent(
            -s * 10,
            0,
          ),
          const SingleActivator(LogicalKeyboardKey.home): const _MoveIntent(
            -1,
            0,
          ),
          const SingleActivator(LogicalKeyboardKey.end): const _MoveIntent(
            1,
            0,
          ),
        },
        actions: {
          _MoveIntent: CallbackAction<_MoveIntent>(onInvoke: (i) => move(i.dx)),
        },
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            void at(Offset p) => widget.onChanged((p.dx / w).clamp(0, 1));
            return GestureDetector(
              onPanDown: (d) => at(d.localPosition),
              onPanUpdate: (d) => at(d.localPosition),
              child: SizedBox(
                height: 16,
                child: CustomPaint(
                  painter: _StripPainter(
                    paintStrip: widget.paint,
                    value: widget.value,
                    thumb: widget.thumb,
                    edge: c.background,
                    ring: _focused ? c.ring : c.border,
                    focused: _focused,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.paintStrip,
    required this.value,
    required this.thumb,
    required this.edge,
    required this.ring,
    required this.focused,
  });

  final void Function(Canvas, Rect) paintStrip;
  final double value;
  final Color thumb, edge, ring;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 3, size.width, size.height - 6);
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height / 2),
    );
    canvas.save();
    canvas.clipRRect(shape);
    paintStrip(canvas, rect);
    canvas.restore();
    final at = Offset(
      (value * size.width).clamp(size.height / 2, size.width - size.height / 2),
      size.height / 2,
    );
    canvas.drawCircle(at, size.height / 2, Paint()..color = edge);
    canvas.drawCircle(
      at,
      size.height / 2 - 2.5,
      Paint()..color = thumb.withValues(alpha: 1),
    );
    canvas.drawCircle(
      at,
      size.height / 2,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = focused ? 2 : 1,
    );
  }

  @override
  bool shouldRepaint(_StripPainter old) => true;
}

/// A swatch and its hex that opens a [ColorPicker] under it.
///
/// ```dart
/// ColorPickerButton(value: brand, onChanged: (c) => setState(() => brand = c), label: 'Primary')
/// ```
class ColorPickerButton extends StatelessWidget {
  const ColorPickerButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.alpha = false,
    this.swatches,
  });

  final Color value;
  final ValueChanged<Color> onChanged;

  /// Written before the hex, and what a screen reader calls it.
  final String? label;
  final bool alpha;
  final List<Color>? swatches;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final hex = '#${colorHex(value, alpha: alpha)}';
    return Popover(
      width: 272,
      content: (context) => Padding(
        padding: const EdgeInsets.all(4),
        child: ColorPicker(
          value: value,
          onChanged: onChanged,
          alpha: alpha,
          swatches: swatches,
          semanticLabel: label ?? 'Colour',
        ),
      ),
      builder: (context, controller) => Pressable(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        semanticLabel: label == null ? 'Colour $hex' : '$label, $hex',
        expanded: controller.isOpen,
        builder: (context, state) => AnimatedContainer(
          duration: t.duration,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: state.hovered ? c.accent : c.background,
            borderRadius: BorderRadius.circular(t.radiusMd),
            border: Border.all(color: state.focused ? c.ring : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: value,
                  borderRadius: BorderRadius.circular(t.radiusSm),
                  border: Border.all(color: c.border),
                ),
              ),
              const SizedBox(width: 8),
              if (label != null) ...[
                Text(label!, style: t.text.sm.copyWith(color: c.foreground)),
                const SizedBox(width: 8),
              ],
              Text(
                hex,
                style: t.text.xs.copyWith(
                  color: c.mutedForeground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
