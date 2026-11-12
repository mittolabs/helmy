/// CSS values as Dart source for Flutter: lengths (px, em, rem, vw, vh, and
/// clamp, min, max, calc of them), colors, shadows, gradients, borders.
/// Each returns the code that computes the same value, or null for what it
/// cannot say (outside the subset, which the checker reports).
library;

import 'dart:math' as math;

/// A length as Dart: a number (`24.0`), or an expression of the screen's
/// width (`vw(context, 5)`), with whether it needs `context`.
class DLen {
  const DLen(this.code, {this.dynamic = false, this.value});
  final String code;
  final bool dynamic;

  /// Its value in px, when known without the screen.
  final double? value;

  static DLen px(double v) => DLen(_num(v), value: v);
  bool get isZero => value == 0;
}

String _num(double v) {
  if (v == v.roundToDouble()) return '${v.toInt()}.0';
  final s = v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? '${s}0' : s;
}

String num(double v) => _num(v);

/// [text] as a length, its em against [fontSize]; null for `auto`, a
/// percentage, or what it cannot read.
DLen? length(String text, {double fontSize = 16}) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty || t == 'auto' || t == 'none' || t.endsWith('%')) return null;
  return _expr(t, fontSize);
}

DLen? _expr(String t, double fontSize) {
  final fn = RegExp(r'^(clamp|min|max|calc)\((.*)\)$').firstMatch(t);
  if (fn != null) {
    final args = splitTop(fn[2]!, ',');
    if (fn[1] == 'calc') return _calc(fn[2]!, fontSize);
    final parts = [for (final a in args) _expr(a.trim(), fontSize)];
    if (parts.any((p) => p == null)) return null;
    final p = parts.cast<DLen>();
    switch (fn[1]) {
      case 'clamp':
        if (p.length != 3) return null;
        if (!p[1].dynamic && p[1].value != null) {
          return DLen.px(p[1].value!.clamp(p[0].value ?? 0, p[2].value ?? double.infinity));
        }
        return DLen('(${p[1].code}).clamp(${p[0].code}, ${p[2].code})', dynamic: true);
      case 'min':
      case 'max':
        if (p.every((x) => x.value != null && !x.dynamic)) {
          final vs = p.map((x) => x.value!);
          return DLen.px(fn[1] == 'min' ? vs.reduce(math.min) : vs.reduce(math.max));
        }
        return DLen(p.map((x) => x.code).reduce((a, b) => 'math.${fn[1]}($a, $b)'), dynamic: true);
    }
  }
  final m = RegExp(r'^(-?[\d.]+)(px|em|rem|vw|vh)?$').firstMatch(t);
  if (m == null) return null;
  final v = double.tryParse(m[1]!);
  if (v == null) return null;
  return switch (m[2]) {
    null || 'px' => DLen.px(v),
    'em' => DLen.px(v * fontSize),
    'rem' => DLen.px(v * 16),
    'vw' => DLen('vw(context, ${_num(v)})', dynamic: true),
    'vh' => DLen('vh(context, ${_num(v)})', dynamic: true),
    _ => null,
  };
}

/// `calc(a + b * 2)`: operands (lengths, clamps, numbers) joined by the
/// operators between them, read outside brackets.
DLen? _calc(String body, double fontSize) {
  final out = StringBuffer();
  var depth = 0;
  var start = 0;
  final text = body.trim();
  bool operand(String part) {
    final p = part.trim();
    if (p.isEmpty) return true;
    final inner = p.startsWith('(') && p.endsWith(')')
        ? _calc(p.substring(1, p.length - 1), fontSize)
        : _expr(p, fontSize);
    final n = inner ?? (double.tryParse(p) == null ? null : DLen.px(double.parse(p)));
    if (n == null) return false;
    out.write(n.code);
    return true;
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (depth != 0) continue;
    // + and - are operators only with space around them, as CSS has it.
    final isOp =
        (ch == '*' || ch == '/') ||
        ((ch == '+' || ch == '-') &&
            i > 0 &&
            text[i - 1] == ' ' &&
            i + 1 < text.length &&
            text[i + 1] == ' ');
    if (!isOp) continue;
    if (!operand(text.substring(start, i))) return null;
    out.write(' $ch ');
    start = i + 1;
  }
  if (!operand(text.substring(start))) return null;
  return DLen('(${out.toString().trim()})', dynamic: true);
}

/// [text] split at [sep] outside brackets.
List<String> splitTop(String text, String sep) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (depth == 0 && text.startsWith(sep, i)) {
      out.add(text.substring(start, i));
      start = i + sep.length;
    }
  }
  out.add(text.substring(start));
  return out.where((s) => s.trim().isNotEmpty).toList();
}

/// The 1 to 4 values of `margin`/`padding` as top, right, bottom, left.
List<String> sides(String text) {
  final v = splitTop(text.trim(), ' ');
  return switch (v.length) {
    1 => [v[0], v[0], v[0], v[0]],
    2 => [v[0], v[1], v[0], v[1]],
    3 => [v[0], v[1], v[2], v[1]],
    _ => [v[0], v[1], v[2], v[3]],
  };
}

// ---- Colors -------------------------------------------------------------------

/// A color's ARGB, or null when it is not one.
int? colorValue(String text) {
  final t = text.trim().toLowerCase();
  if (t == 'transparent') return 0x00000000;
  if (_named[t] case final v?) return v;
  final hex = RegExp(r'^#([0-9a-f]{3,8})$').firstMatch(t);
  if (hex != null) {
    var h = hex[1]!;
    if (h.length == 3 || h.length == 4) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6) return 0xFF000000 | int.parse(h, radix: 16);
    if (h.length == 8) {
      final rgb = int.parse(h.substring(0, 6), radix: 16);
      final a = int.parse(h.substring(6), radix: 16);
      return (a << 24) | rgb;
    }
    return null;
  }
  final rgb = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(t);
  if (rgb != null) {
    final p = rgb[1]!.split(RegExp(r'[\s,/]+')).where((s) => s.isNotEmpty).toList();
    if (p.length < 3) return null;
    int ch(String s) => s.endsWith('%')
        ? (double.parse(s.substring(0, s.length - 1)) * 2.55).round()
        : double.parse(s).round();
    final a = p.length > 3
        ? (p[3].endsWith('%')
              ? double.parse(p[3].substring(0, p[3].length - 1)) / 100
              : double.parse(p[3]))
        : 1.0;
    return ((a * 255).round() << 24) |
        (ch(p[0]).clamp(0, 255) << 16) |
        (ch(p[1]).clamp(0, 255) << 8) |
        ch(p[2]).clamp(0, 255);
  }
  final hsl = RegExp(r'^hsla?\(([^)]*)\)$').firstMatch(t);
  if (hsl != null) {
    final p = hsl[1]!.split(RegExp(r'[\s,/]+')).where((s) => s.isNotEmpty).toList();
    if (p.length < 3) return null;
    final h = double.parse(p[0].replaceAll('deg', '')) / 360;
    final s = double.parse(p[1].replaceAll('%', '')) / 100;
    final l = double.parse(p[2].replaceAll('%', '')) / 100;
    final a = p.length > 3
        ? double.parse(p[3].replaceAll('%', '')) / (p[3].endsWith('%') ? 100 : 1)
        : 1.0;
    double hue(double p, double q, double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }

    final q = l < .5 ? l * (1 + s) : l + s - l * s;
    final pp = 2 * l - q;
    final r = (hue(pp, q, h + 1 / 3) * 255).round(),
        g = (hue(pp, q, h) * 255).round(),
        b = (hue(pp, q, h - 1 / 3) * 255).round();
    return ((a * 255).round() << 24) | (r << 16) | (g << 8) | b;
  }
  return null;
}

const _named = {
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
  'red': 0xFFFF0000,
  'green': 0xFF008000,
  'blue': 0xFF0000FF,
  'gray': 0xFF808080,
  'grey': 0xFF808080,
};

String colorCode(int argb) => 'Color(0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()})';

/// Every color in [text] with where it is: for shadows, borders, gradients.
final colorPattern = RegExp(
  r'#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\)|\btransparent\b|\b(black|white)\b',
);

// ---- Shadows, borders, gradients ---------------------------------------------

/// `box-shadow` as a list of BoxShadow; null for an inset shadow.
String? shadows(String text, String Function(int argb) color) {
  if (text.trim() == 'none') return 'const []';
  final out = <String>[];
  for (final one in splitTop(text, ',')) {
    if (one.contains('inset')) return null;
    final c = colorPattern.firstMatch(one);
    final argb = c == null ? 0xFF000000 : colorValue(c[0]!);
    if (argb == null) return null;
    final rest = c == null ? one : one.replaceFirst(c[0]!, '');
    final nums = [
      for (final p in rest.trim().split(RegExp(r'\s+')))
        if (p.isNotEmpty) length(p),
    ];
    if (nums.any((n) => n == null || n.dynamic) || nums.length < 2) return null;
    final n = nums.cast<DLen>().map((l) => l.value!).toList();
    final blur = n.length > 2 ? n[2] : 0.0;
    final spread = n.length > 3 ? n[3] : 0.0;
    out.add(
      'BoxShadow(color: ${color(argb)}, offset: Offset(${_num(n[0])}, ${_num(n[1])}), '
      // CSS blur is a radius twice Flutter's sigma; BoxShadow's blurRadius
      // follows CSS.
      'blurRadius: ${_num(blur)}, spreadRadius: ${_num(spread)})',
    );
  }
  return '[${out.join(', ')}]';
}

/// `1px solid #333` as a BorderSide; null for what it cannot say.
String? borderSide(String text, String Function(int argb) color, {String? current}) {
  final t = text.trim();
  if (t == 'none' || t == '0') return 'BorderSide.none';
  var width = 3.0; // CSS's medium
  String? col;
  var none = false;
  for (final part in splitTop(t, ' ')) {
    final l = length(part);
    if (l != null && l.value != null) {
      width = l.value!;
      continue;
    }
    if (part == 'none' || part == 'hidden') none = true;
    if (part == 'solid') continue;
    final c = colorValue(part);
    if (c != null) col = color(c);
    if (part == 'currentcolor' || part == 'currentColor') col = current;
  }
  if (none || width == 0) return 'BorderSide.none';
  return 'BorderSide(color: ${col ?? current ?? 'const Color(0xFF000000)'}, width: ${_num(width)})';
}

/// `linear-gradient(...)`/`radial-gradient(...)` as a Gradient; null otherwise.
String? gradient(String text, String Function(int argb) color) {
  final m = RegExp(r'^(linear|radial)-gradient\((.*)\)$').firstMatch(text.trim());
  if (m == null) return null;
  final args = splitTop(m[2]!, ',').map((s) => s.trim()).toList();
  var angle = 180.0; // to bottom
  var first = 0;
  String? center;
  if (m[1] == 'linear') {
    final a = args.first;
    final deg = RegExp(r'^(-?[\d.]+)deg$').firstMatch(a);
    if (deg != null) {
      angle = double.parse(deg[1]!);
      first = 1;
    } else if (a.startsWith('to ')) {
      angle = switch (a) {
        'to top' => 0,
        'to right' => 90,
        'to bottom' => 180,
        'to left' => 270,
        'to top right' || 'to right top' => 45,
        'to bottom right' || 'to right bottom' => 135,
        'to bottom left' || 'to left bottom' => 225,
        'to top left' || 'to left top' => 315,
        _ => 180,
      };
      first = 1;
    }
  } else if (!colorPattern.hasMatch(args.first)) {
    // Radial: its shape and place, read only for "at x y".
    final at = RegExp(r'at\s+([\d.]+)%\s+([\d.]+)%').firstMatch(args.first);
    if (at != null) {
      center =
          'Alignment(${_num(double.parse(at[1]!) / 50 - 1)}, ${_num(double.parse(at[2]!) / 50 - 1)})';
    }
    first = 1;
  }
  final colors = <String>[];
  final stops = <double?>[];
  for (final stop in args.skip(first)) {
    final c = colorPattern.firstMatch(stop);
    final argb = c == null ? null : colorValue(c[0]!);
    if (argb == null) return null;
    colors.add(color(argb));
    final pct = RegExp(r'([\d.]+)%').firstMatch(stop.replaceFirst(c![0]!, ''));
    stops.add(pct == null ? null : double.parse(pct[1]!) / 100);
  }
  if (colors.length < 2) return null;
  // Stops not given are spread evenly, as CSS does.
  stops[0] ??= 0;
  stops[stops.length - 1] ??= 1;
  for (var i = 1; i < stops.length - 1; i++) {
    if (stops[i] != null) continue;
    var j = i;
    while (stops[j] == null) {
      j++;
    }
    final a = stops[i - 1]!, b = stops[j]!;
    for (var k = i; k < j; k++) {
      stops[k] = a + (b - a) * (k - i + 1) / (j - i + 1);
    }
  }
  final stopCode = '[${stops.map((s) => _num(s!)).join(', ')}]';
  if (m[1] == 'radial') {
    return 'RadialGradient(center: ${center ?? 'Alignment.center'}, radius: 0.75, colors: [${colors.join(', ')}], stops: $stopCode)';
  }
  // CSS's angle: 0 points up, turning clockwise.
  final r = angle * math.pi / 180;
  final dx = math.sin(r), dy = -math.cos(r);
  return 'LinearGradient(begin: Alignment(${_num(-dx)}, ${_num(-dy)}), end: Alignment(${_num(dx)}, ${_num(dy)}), '
      'colors: [${colors.join(', ')}], stops: $stopCode)';
}

/// [text]'s value in px at a screen [width] wide: clamp, min, max and vw
/// worked out, for what needs a number (em against a size that follows the
/// screen).
double? cssPx(String text, {double width = 1440, double height = 900, double fontSize = 16}) {
  final t = text.trim().toLowerCase();
  final fn = RegExp(r'^(clamp|min|max)\((.*)\)$').firstMatch(t);
  if (fn != null) {
    final args = [
      for (final a in splitTop(fn[2]!, ','))
        cssPx(a, width: width, height: height, fontSize: fontSize),
    ];
    if (args.any((a) => a == null)) return null;
    final v = args.cast<double>();
    return switch (fn[1]) {
      'clamp' => v[1].clamp(v[0], v[2]),
      'min' => v.reduce(math.min),
      _ => v.reduce(math.max),
    };
  }
  final m = RegExp(r'^(-?[\d.]+)(px|em|rem|vw|vh)?$').firstMatch(t);
  if (m == null) return null;
  final n = double.parse(m[1]!);
  return switch (m[2]) {
    'vw' => n * width / 100,
    'vh' => n * height / 100,
    'em' => n * fontSize,
    'rem' => n * 16,
    _ => n,
  };
}
