import 'design_model.dart';
import 'reader.dart';

/// The CSS a design keeps to so that it converts 1:1 to Flutter (and later
/// SwiftUI and Compose): layout by flex, sizes, spacing, color, borders,
/// corners, shadows, type and pictures, each with a direct equal there.
/// What falls outside it still draws on the canvas, and exports to the web
/// and React exactly; it is what a Flutter export cannot promise.
///
/// Also what agents are told when they draw (identity.dart): kept to, the
/// checker finds nothing.
const subsetForAgents =
    'Keep each screen inside the CSS that converts exactly to app code: lay out with flexbox '
    '(display flex, flex-direction, flex-wrap, justify-content, align-items, gap, flex), never '
    'grid, float, tables or position fixed, or sticky except on a header that is the body\'s '
    'first element at top 0; size with px, %, em, rem, vw, vh and '
    'clamp, min, max or calc of those; style with color, background (a color, a linear or '
    'radial gradient, or an image), border, border-radius, box-shadow, opacity, overflow, '
    'transform (translate, scale, rotate), backdrop-filter blur, and type (font-family naming '
    'first a font the page loads from Google Fonts with a <link>, never a system font such as '
    'ui-monospace or -apple-system, which an app cannot bundle; '
    'font-size, font-weight, font-style, line-height, letter-spacing, text-align, '
    'text-decoration, text-transform, white-space nowrap, text-overflow ellipsis); position '
    'absolute inside a position relative parent for layering. A <style> block holds only '
    '@media (max-width) rules that switch a class\'s display, order or flex-direction.';

/// One thing in a screen that will not convert 1:1 to Flutter.
class SubsetIssue {
  SubsetIssue({
    required this.file,
    required this.selector,
    required this.what,
    required this.why,
    this.element,
  });

  /// The screen's file.
  final String file;

  /// Where in the page, as `querySelector` finds it; `style` for its
  /// `<style>` block.
  final String selector;

  /// What is outside: `display: grid`.
  final String what;

  /// Why, and what to write instead, in a sentence.
  final String why;

  /// Its element's opening, for reading in a list: `<div class="cards">`.
  final String? element;

  Map<String, Object?> toJson() => {'file': file, 'selector': selector, 'what': what, 'why': why};
}

/// Everything in [screen] outside the subset, in page order.
List<SubsetIssue> checkSubset(DScreen screen) {
  final out = <SubsetIssue>[];
  void add(DNode n, String what, String why) => out.add(
    SubsetIssue(
      file: screen.file,
      selector: n.selector,
      what: what,
      why: why,
      element: '<${n.tag}${n.classes.isEmpty ? '' : ' class="${n.classes.join(' ')}"'}>',
    ),
  );

  final loaded = loadedFonts(screen);
  for (final n in [screen.body, ...screen.body.descendants]) {
    if (n.isText) continue;
    if (_tags[n.tag] case final why?) add(n, '<${n.tag}>', why);
    if (_firstFamily(n.style) case (final key, final value, final family)
        when !loaded.contains(family.toLowerCase())) {
      add(
        n,
        '$key: $value',
        '$family is not loaded from Google Fonts, so an app cannot bundle it and draws another '
            'font in its place. Load a Google Font with the page\'s <link> and name it first.',
      );
    }
    for (final e in n.style.entries) {
      // A header stuck to the top converts: pinned over the page.
      if (e.key == 'position' && identical(n, stickyHeader(screen.body))) continue;
      final why = _checkProperty(e.key, e.value);
      if (why != null) add(n, '${e.key}: ${e.value}', why);
    }
  }
  for (final why in _checkCss(screen.css)) {
    out.add(SubsetIssue(file: screen.file, selector: 'style', what: why.$1, why: why.$2));
  }
  return out;
}

/// The body's first element when it sticks at the top (position: sticky;
/// top: 0): what an app pins over the page as it scrolls.
DNode? stickyHeader(DNode body) {
  final first = body.children.where((c) => !c.isText).firstOrNull;
  if (first == null || first.style['position'] != 'sticky') return null;
  final top = first.style['top']?.trim();
  return top == '0' || top == '0px' ? first : null;
}

/// The families [screen] loads from Google Fonts, lower case.
Set<String> loadedFonts(DScreen screen) => {
  for (final l in screen.links)
    if (RegExp(r'href="([^"]+)"').firstMatch(l)?[1] case final h?
        when h.contains('fonts.googleapis.com'))
      for (final spec
          in Uri.parse(h.replaceAll('&amp;', '&')).queryParametersAll['family'] ?? const <String>[])
        spec.split(':').first.replaceAll('+', ' ').toLowerCase(),
};

/// The style's font-family (or font) and the family it names first.
(String, String, String)? _firstFamily(Map<String, String> style) {
  String? list;
  String? key;
  if (style['font-family'] case final f?) {
    (key, list) = ('font-family', f);
  } else if (style['font'] case final f?) {
    final m = RegExp(
      r'^(?:(?:italic|oblique|normal|bold|bolder|lighter|small-caps|\d{3})\s+)*[\d.]+(?:px|em|rem|%|pt)(?:\s*/\s*\S+)?\s+(.+)$',
    ).firstMatch(f.trim());
    if (m != null) (key, list) = ('font', m[1]!);
  }
  if (list == null || key == null) return null;
  final first = list.split(',').first.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
  if (first.isEmpty || const {'inherit', 'initial', 'unset'}.contains(first)) return null;
  return (key, style[key]!, first);
}

/// Every screen of the design in [folder], checked.
Future<List<SubsetIssue>> checkDesign(String folder) async {
  final d = await readDesign(folder);
  return [for (final s in d.screens) ...checkSubset(s)];
}

const _tags = {
  'table': 'Tables have no 1:1 equal; lay rows out with flex.',
  'iframe': 'A page inside a page does not convert; link to it instead.',
  'canvas': 'A drawing canvas is code, not design; use an image or an SVG.',
  'video': 'Video does not convert yet; use an image of its first frame.',
  'audio': 'Audio does not convert.',
  'select': 'A native drop-down does not convert yet; draw it as a button with a chevron.',
};

/// Properties that change nothing an export draws: left alone.
const _ignored = {
  'cursor',
  'transition',
  'transition-property',
  'transition-duration',
  'transition-timing-function', //
  'animation', 'animation-name', 'animation-duration', '-webkit-font-smoothing',
  '-moz-osx-font-smoothing', 'box-sizing', 'pointer-events', 'user-select', '-webkit-user-select',
  'will-change', 'text-rendering', 'font-feature-settings', 'font-optical-sizing',
  '-webkit-tap-highlight-color', 'scroll-behavior', 'content-visibility', 'resize', 'appearance',
  '-webkit-appearance', 'outline-offset', 'text-underline-offset', 'text-decoration-thickness',
  'text-decoration-color', 'text-decoration-line', 'text-decoration-style', 'list-style',
  'list-style-type', 'tab-size', 'hyphens', 'word-break', 'overflow-wrap', 'word-wrap',
  'vertical-align', 'isolation', 'contain',
};

/// What each property in the subset may be: true for any value of the
/// allowed units, or the words it may take.
const Map<String, Object> _allowed = {
  'display': {'block', 'flex', 'inline-flex', 'inline', 'inline-block', 'none'},
  'flex-direction': {'row', 'column', 'row-reverse', 'column-reverse'},
  'flex-wrap': {'wrap', 'nowrap'},
  'justify-content': {
    'flex-start',
    'flex-end',
    'center',
    'space-between',
    'space-around',
    'space-evenly',
    'start',
    'end',
    'normal',
  },
  'align-items': {
    'flex-start',
    'flex-end',
    'center',
    'stretch',
    'baseline',
    'start',
    'end',
    'normal',
  },
  'align-self': {'flex-start', 'flex-end', 'center', 'stretch', 'baseline', 'start', 'end', 'auto'},
  'place-items': {'center', 'start', 'end', 'stretch', 'normal'},
  'place-content': {'center', 'start', 'end', 'stretch', 'normal'},
  'justify-items': {'center', 'start', 'end', 'stretch', 'normal'},
  'font': true,
  'align-content': {
    'flex-start',
    'flex-end',
    'center',
    'stretch',
    'space-between',
    'start',
    'end',
    'normal',
  },
  'flex': true,
  'flex-grow': true,
  'flex-shrink': true,
  'flex-basis': true,
  'order': true,
  'gap': true,
  'row-gap': true,
  'column-gap': true,
  'width': true,
  'height': true,
  'min-width': true,
  'min-height': true,
  'max-width': true,
  'max-height': true,
  'aspect-ratio': true,
  'margin': true,
  'margin-top': true,
  'margin-right': true,
  'margin-bottom': true,
  'margin-left': true,
  'margin-inline': true,
  'margin-block': true,
  'padding': true,
  'padding-top': true,
  'padding-right': true,
  'padding-bottom': true,
  'padding-left': true,
  'padding-inline': true,
  'padding-block': true,
  'position': {'static', 'relative', 'absolute'},
  'top': true,
  'right': true,
  'bottom': true,
  'left': true,
  'inset': true,
  'z-index': true,
  'color': true,
  'background': true,
  'background-color': true,
  'background-image': true,
  'background-size': true,
  'background-position': true,
  'background-repeat': true,
  'background-clip': {'border-box', 'padding-box', 'content-box', 'text'},
  '-webkit-background-clip': {'border-box', 'padding-box', 'content-box', 'text'},
  '-webkit-text-fill-color': true,
  'border': true,
  'border-top': true,
  'border-right': true,
  'border-bottom': true,
  'border-left': true,
  'border-width': true,
  'border-style': {'solid', 'none'},
  'border-color': true,
  'border-top-width': true,
  'border-bottom-width': true,
  'border-left-width': true,
  'border-right-width': true,
  'border-top-color': true,
  'border-bottom-color': true,
  'border-left-color': true,
  'border-right-color': true,
  'border-radius': true,
  'border-top-left-radius': true,
  'border-top-right-radius': true,
  'border-bottom-left-radius': true,
  'border-bottom-right-radius': true,
  'outline': true,
  'box-shadow': true,
  'opacity': true,
  'overflow': {'hidden', 'visible', 'auto', 'scroll', 'clip'},
  'overflow-x': {'hidden', 'visible', 'auto', 'scroll', 'clip'},
  'overflow-y': {'hidden', 'visible', 'auto', 'scroll', 'clip'},
  'transform': true,
  'transform-origin': true,
  'backdrop-filter': true,
  '-webkit-backdrop-filter': true,
  'filter': true,
  'font-family': true,
  'font-size': true,
  'font-weight': true,
  'font-style': {'normal', 'italic'},
  'line-height': true,
  'letter-spacing': true,
  'text-align': {'left', 'right', 'center', 'justify', 'start', 'end'},
  'text-decoration': true,
  'text-transform': {'none', 'uppercase', 'lowercase', 'capitalize'},
  'white-space': {'normal', 'nowrap', 'pre', 'pre-wrap', 'pre-line'},
  'text-overflow': {'clip', 'ellipsis'},
  '-webkit-line-clamp': true,
  '-webkit-box-orient': {'vertical'},
  'object-fit': {'cover', 'contain', 'fill', 'none', 'scale-down'},
  'object-position': true,
};

/// Why [prop]: [value] is outside the subset; null when it is inside.
String? _checkProperty(String prop, String value) {
  if (_ignored.contains(prop) || prop.startsWith('--')) return null;
  final v = value.replaceAll('!important', '').trim().toLowerCase();
  // A grid converts when its columns are fixed: px and fr tracks (rows of
  // equal or sized cells), or none at all (one cell, to center or stack).
  if (prop == 'display' && (v == 'grid' || v == 'inline-grid')) return null;
  if (prop == 'grid-template-columns') {
    final tracks = v.replaceAllMapped(
      RegExp(r'repeat\(\s*(\d+)\s*,\s*([^)]+)\)'),
      (m) => List.filled(int.parse(m[1]!), m[2]!.trim()).join(' '),
    );
    if (RegExp(r'^((\d*\.?\d+(px|fr))\s*)+$').hasMatch(tracks.trim())) return null;
    // As many equal columns as fit at a least width: worked out exactly.
    final fit = RegExp(r'^repeat\((auto-fill|auto-fit),minmax\((min\(100%,)?[\d.]+px\)?,1fr\)\)$');
    if (fit.hasMatch(v.replaceAll(' ', ''))) return null;
    return 'Only fixed columns convert (repeat(3, 1fr), 240px 1fr); auto-fit and minmax do not: '
        'use flex-wrap.';
  }
  if (prop.startsWith('grid')) {
    return "$prop does not convert; cells fill a grid's columns in order.";
  }
  if (prop == 'position' && (v == 'fixed' || v == 'sticky')) {
    return 'Fixed and sticky positions do not convert yet; leave it in the flow.';
  }
  if (prop == 'float' || prop == 'clear') return 'Floats do not convert; use flex.';
  // With -webkit-line-clamp: its lines clamped.
  if (prop == 'display' && v == '-webkit-box') return null;
  final rule = _allowed[prop];
  if (rule == null) return '$prop does not convert to app code.';
  if (rule is Set<String> && !rule.contains(v)) {
    return '$prop: $v does not convert; one of ${rule.join(', ')}.';
  }
  if (prop == 'filter' || prop.endsWith('backdrop-filter')) {
    final fns = RegExp(r'([a-z-]+)\(').allMatches(v).map((m) => m[1]).toSet()
      ..removeAll(const ['rgb', 'rgba', 'hsl', 'hsla', 'var', 'calc']);
    // Blur and what a color matrix can do; drop-shadow too on the element
    // itself (filter), not behind it (backdrop-filter).
    final other = fns.difference(
      prop == 'filter'
          ? const {
              'blur',
              'drop-shadow',
              'saturate',
              'brightness',
              'contrast',
              'opacity',
              'invert',
              'grayscale',
              'sepia',
              'hue-rotate',
            }
          : const {
              'blur',
              'saturate',
              'brightness',
              'contrast',
              'opacity',
              'invert',
              'grayscale',
              'sepia',
              'hue-rotate',
            },
    );
    if (other.isNotEmpty) {
      return prop == 'filter'
          ? '${other.join(', ')} in $prop does not convert; blur, drop-shadow and color changes do.'
          : '${other.join(', ')} in $prop does not convert; blur and color changes do.';
    }
  }
  if (prop == 'transform') {
    final fns = RegExp(r'([a-zA-Z0-9]+)\(').allMatches(v).map((m) => m[1]!.toLowerCase()).toSet();
    final other = fns.difference({
      'translate',
      'translatex',
      'translatey',
      'scale',
      'scalex',
      'scaley',
      'rotate',
    });
    if (other.isNotEmpty) {
      return '${other.join(', ')} does not convert; translate, scale and rotate do.';
    }
  }
  // Numbers with units, once colors, words in quotes, links and function
  // names are out of the way.
  final numbers = v
      .replaceAll(RegExp(r'#[0-9a-f]+'), ' ')
      .replaceAll(RegExp(r'''('[^']*'|"[^"]*")'''), ' ')
      .replaceAll(RegExp(r'url\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[a-z-]+[0-9]*[a-z]*\('), '(');
  final bad = RegExp(r'(?<![a-z])(-?[\d.]+)([a-z%]+)')
      .allMatches(numbers)
      .map((m) => m[2]!)
      .where((u) => !_units.contains(u))
      .toSet();
  if (bad.isNotEmpty) return '${bad.join(', ')} does not convert; px, %, em, rem, vw or vh do.';
  return null;
}

const _units = {'px', '%', 'em', 'rem', 'vw', 'vh', 'deg', 'turn', 's', 'ms', 'x', 'fr'};

/// A `<style>` block may only switch classes by width: `@media (max-width:
/// 720px) { .hide-sm { display: none } }`. Anything else, one issue each.
List<(String, String)> _checkCss(String css) {
  final out = <(String, String)>[];
  final noComments = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  var rest = noComments;
  final media = RegExp(
    r'@media\s*\(\s*(max|min)-width\s*:\s*[\d.]+px\s*\)\s*\{((?:[^{}]*\{[^{}]*\})*)\s*\}',
  );
  for (final m in media.allMatches(noComments)) {
    rest = rest.replaceFirst(m[0]!, '');
    for (final r in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(m[2]!)) {
      final selector = r[1]!.trim();
      if (!RegExp(r'^\.[\w-]+(\s*,\s*\.[\w-]+)*$').hasMatch(selector)) {
        out.add((selector, 'Only class names may be switched by width.'));
        continue;
      }
      for (final e in parseStyle(r[2]!).entries) {
        if (!{'display', 'order', 'flex-direction'}.contains(e.key)) {
          out.add((
            '${e.key}: ${e.value}',
            'By width, only display, order and flex-direction convert.',
          ));
        }
      }
    }
  }
  final left = rest.trim();
  if (left.isNotEmpty) {
    for (final r in RegExp(r'([^{}]+)\{').allMatches(left)) {
      out.add((
        r[1]!.trim(),
        'A stylesheet rule does not convert; put it in the element\'s style.',
      ));
    }
  }
  return out;
}
