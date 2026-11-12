/// Widgets a Flutter export brings with it, as source for the
/// export's `lib/ui/core/design.dart`.
///
/// Flutter rounds every line of a paragraph to a whole pixel (a 25.6px line is
/// laid out 26px tall, on every engine), so a paragraph of ten lines ends 4px
/// lower than the page's. The engine's line metrics keep the exact values
/// (ascent and descent, leading included, add up to the line height CSS
/// uses, and the ascent is where CSS puts the baseline), so CssText lets
/// Flutter break the lines and then places each one where the page does.
library;

const cssTextSource = r'''
/// Text as the page lays it out: Flutter breaks the lines, and each line is
/// placed at its exact height, where Flutter alone would round each to a
/// whole pixel.
class CssText extends StatelessWidget {
  const CssText(this.text, {super.key, this.textAlign = TextAlign.start, this.softWrap = true});
  final TextSpan text;
  final TextAlign textAlign;
  final bool softWrap;

  @override
  Widget build(BuildContext context) => _CssText(
    text: TextSpan(style: DefaultTextStyle.of(context).style, children: [text]),
    textAlign: textAlign,
    softWrap: softWrap,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
  );
}

class _CssText extends LeafRenderObjectWidget {
  const _CssText({
    required this.text,
    required this.textAlign,
    required this.softWrap,
    required this.textDirection,
    required this.textScaler,
  });
  final TextSpan text;
  final TextAlign textAlign;
  final bool softWrap;
  final TextDirection textDirection;
  final TextScaler textScaler;

  @override
  RenderCssText createRenderObject(BuildContext context) =>
      RenderCssText(text, textAlign, softWrap, textDirection, textScaler);

  @override
  void updateRenderObject(BuildContext context, RenderCssText renderObject) => renderObject
    ..text = text
    ..textAlign = textAlign
    ..softWrap = softWrap
    ..textDirection = textDirection
    ..textScaler = textScaler
    ..markNeedsLayout();
}

/// One line: drawn by its own painter (its baseline [own] below its top),
/// [x] across, its baseline at [baseline]; it runs from [top] to [bottom].
typedef _CssLine = ({
  TextPainter painter,
  double x,
  double baseline,
  double own,
  double top,
  double bottom,
});

class RenderCssText extends RenderBox {
  RenderCssText(this.text, this.textAlign, this.softWrap, this.textDirection, this.textScaler);
  TextSpan text;
  TextAlign textAlign;
  bool softWrap;
  TextDirection textDirection;
  TextScaler textScaler;

  List<_CssLine> _lines = const [];
  double _baseline = 0;

  TextPainter _painter(InlineSpan span, {TextAlign align = TextAlign.start}) =>
      TextPainter(text: span, textAlign: align, textDirection: textDirection, textScaler: textScaler);

  /// The lines at [maxWidth], their height and the first baseline.
  (List<_CssLine>, Size, double) _layout(double maxWidth) {
    final full = _painter(text, align: textAlign)
      ..layout(maxWidth: softWrap ? maxWidth : double.infinity);
    final lines = <_CssLine>[];
    var y = 0.0;
    double? first;
    // A line-height said in the style, or the font's own (normal).
    final inner = text.children?.firstOrNull;
    final said = (inner is TextSpan ? inner.style?.height : null) ?? text.style?.height;
    // The font's ascent and descent, each rounded to a pixel as the page
    // rounds them: where its baseline goes in a line.
    final base = (text.style ?? const TextStyle()).merge(inner is TextSpan ? inner.style : null);
    final plain = _painter(
      TextSpan(
        text: 'x',
        style: TextStyle(
          fontFamily: base.fontFamily,
          fontFamilyFallback: base.fontFamilyFallback,
          fontSize: base.fontSize,
          fontWeight: base.fontWeight,
          fontStyle: base.fontStyle,
          fontVariations: base.fontVariations,
        ),
      ),
    )..layout();
    final pm = plain.computeLineMetrics().firstOrNull;
    final ascent = pm?.ascent.roundToDouble() ?? 0, descent = pm?.descent.roundToDouble() ?? 0;
    plain.dispose();
    double cut(double v) => (64 * v).truncateToDouble() / 64;
    // Flutter spaces letters around each glyph, the page after it: the
    // line's glyphs start that much further along on the page.
    final spacing = base.letterSpacing ?? 0;
    for (final m in full.computeLineMetrics()) {
      final range = full.getLineBoundary(full.getPositionForOffset(Offset(m.left, m.baseline)));
      final painter = _painter(_slice(text, range.start, range.end))..layout();
      final own = painter.computeLineMetrics();
      // As the page measures it: a said height in whole 64ths of a pixel
      // (cut, not rounded), and normal as the font's ascent and descent each
      // rounded to a pixel.
      final height = said != null
          ? (64 * (m.ascent + m.descent)).floorToDouble() / 64
          : (m.ascent.roundToDouble() + m.descent.roundToDouble());
      // Half of what the line has beyond the font goes above it.
      final baseline = said != null && pm != null
          ? y + ascent + cut((height - ascent - descent) / 2)
          : y + m.ascent.roundToDouble();
      if (own.isNotEmpty) {
        lines.add((
          painter: painter,
          x: m.left - spacing,
          baseline: baseline,
          own: own.first.baseline,
          top: y,
          bottom: y + height,
        ));
      }
      first ??= baseline;
      y += height;
    }
    final width = full.width;
    full.dispose();
    return (lines, Size(width, y), first ?? 0);
  }

  /// [span]'s text from [start] to [end], with the styles and links it had.
  static TextSpan _slice(TextSpan span, int start, int end) {
    var at = 0;
    TextSpan? cut(InlineSpan s) {
      if (s is! TextSpan) return null;
      final own = s.text ?? '';
      final from = at;
      at += own.length;
      var t = own.substring((start - from).clamp(0, own.length), (end - from).clamp(0, own.length));
      if (t.endsWith('\n')) t = t.substring(0, t.length - 1);
      final kids = <InlineSpan>[
        for (final c in s.children ?? const <InlineSpan>[])
          if (cut(c) case final k?) k,
      ];
      if (t.isEmpty && kids.isEmpty) return null;
      return TextSpan(
        text: t.isEmpty ? null : t,
        style: s.style,
        recognizer: s.recognizer,
        mouseCursor: s.mouseCursor,
        children: kids.isEmpty ? null : kids,
      );
    }

    return cut(span) ?? const TextSpan(text: '');
  }

  void _dispose() {
    for (final l in _lines) {
      l.painter.dispose();
    }
    _lines = const [];
  }

  @override
  void performLayout() {
    _dispose();
    final (lines, s, baseline) = _layout(constraints.maxWidth);
    _lines = lines;
    _baseline = baseline;
    size = constraints.constrain(s);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final (lines, s, _) = _layout(constraints.maxWidth);
    for (final l in lines) {
      l.painter.dispose();
    }
    return constraints.constrain(s);
  }

  double _intrinsic(bool max) {
    final p = _painter(text)..layout();
    final w = max ? p.maxIntrinsicWidth : p.minIntrinsicWidth;
    p.dispose();
    return w;
  }

  @override
  double computeMinIntrinsicWidth(double height) => softWrap ? _intrinsic(false) : _intrinsic(true);

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsic(true);

  @override
  double computeMinIntrinsicHeight(double width) => getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final l in _lines) {
      // Its baseline on a whole pixel, as the page draws text.
      l.painter.paint(
        context.canvas,
        Offset(offset.dx + l.x, (offset.dy + l.baseline).roundToDouble() - l.own),
      );
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final l in _lines) {
      if (position.dy < l.top || position.dy >= l.bottom) continue;
      final local = position - Offset(l.x, l.baseline - l.own);
      if (local.dx < 0 || local.dx > l.painter.width) return false;
      final span = l.painter.text!.getSpanForPosition(l.painter.getPositionForOffset(local));
      if (span is TextSpan) {
        result.add(HitTestEntry(span));
        return true;
      }
    }
    return false;
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = text.toPlainText()
      ..textDirection = textDirection;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }
}
''';

const gridTrackSource = r'''
/// A grid's one column (no grid-template-columns), as CSS sizes it: as wide
/// as its room, or as the widest least width of what is in it when that is
/// wider (a line that does not wrap), past the room as the page lets it.
class GridTrack extends SingleChildRenderObjectWidget {
  const GridTrack({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGridTrack();
}

class RenderGridTrack extends RenderProxyBox {
  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    final room = constraints.maxWidth;
    // What is laid out by its width (a wrapping row, a grid of as many
    // columns as fit) cannot say how narrow it could be, and always wraps to
    // its room: the room it is, then.
    double least;
    try {
      least = c.getMinIntrinsicWidth(double.infinity);
    } on FlutterError {
      least = 0;
    }
    final width = room.isFinite && least > room ? least : room;
    c.layout(
      width.isFinite ? constraints.copyWith(minWidth: width, maxWidth: width) : constraints,
      parentUsesSize: true,
    );
    size = constraints.constrain(c.size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset);
  }
}
''';

const dropShadowSource = r'''
/// CSS's drop-shadow: [child]'s own shape in [color], blurred by [sigma] and
/// moved by [offset], under it. Drawn from the same child, so nothing in it
/// is built twice.
class DropShadow extends SingleChildRenderObjectWidget {
  const DropShadow({super.key, required this.offset, required this.sigma, required this.color, super.child});
  final Offset offset;
  final double sigma;
  final Color color;

  @override
  RenderDropShadow createRenderObject(BuildContext context) => RenderDropShadow(offset, sigma, color);

  @override
  void updateRenderObject(BuildContext context, RenderDropShadow renderObject) => renderObject
    ..shadowOffset = offset
    ..sigma = sigma
    ..color = color
    ..markNeedsPaint();
}

class RenderDropShadow extends RenderProxyBox {
  RenderDropShadow(this.shadowOffset, this.sigma, this.color);
  Offset shadowOffset;
  double sigma;
  Color color;

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    context.pushLayer(
      ImageFilterLayer(imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)),
      (context, offset) => context.pushColorFilter(
        offset,
        ColorFilter.mode(color, BlendMode.srcIn),
        (context, offset) => context.paintChild(c, offset),
      ),
      offset + shadowOffset,
    );
    context.paintChild(c, offset);
  }
}
''';
