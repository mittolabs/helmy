import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_style/dart_style.dart';

import 'design_model.dart';
import 'flutter_css.dart';
import 'flutter_support.dart';
import 'planner.dart';
import 'reader.dart';
import 'subset.dart' show stickyHeader;

/// Which Flutter: Ashlar UI's app, theme and Pressable (Mittolabs' own),
/// or plain widgets for anyone's app. The screens are the same either way.
enum FlutterFlavor { ashlar, plain }

/// A design as a Flutter app on the widgets layer (no Material), laid out as
/// the house architecture has it: a folder per screen under `lib/ui/`, its
/// parts in `widgets/`, shared components and the theme in `lib/ui/core/`.
/// With [measure], each element is keyed by its selector, for comparing
/// where it lands with where the page puts it.
({Map<String, String> files, Set<String> assets, Set<String> fonts}) writeFlutter(
  DesignPlan plan, {
  FlutterFlavor flavor = FlutterFlavor.ashlar,
  bool measure = false,
  String package = 'design_app',
  List<({String family, int weight, bool italic, String asset, bool opsz})> fonts = const [],
  (double, double)? Function(String asset)? imageSize,
}) {
  final w = _FlutterWriter(plan, flavor, measure, package)
    ..fontFiles = fonts
    ..imageSize = imageSize;
  final files = w.files();
  // Formatted as Dart formats itself: code that reads as written by hand.
  final formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
    pageWidth: 100,
  );
  return (
    files: {
      for (final e in files.entries)
        e.key: e.key.endsWith('.dart') ? _format(formatter, e.key, e.value) : e.value,
    },
    assets: w.assets,
    fonts: w.fonts,
  );
}

/// [code] formatted; as written when it does not parse, so the error shows
/// where it is when the app is built.
String _format(DartFormatter f, String path, String code) {
  try {
    return f.format(code, uri: path);
  } on FormatterException catch (e) {
    formatErrors.add('$path: ${e.message()}');
    return code;
  }
}

/// Files that did not parse in the last [writeFlutter]: a converter bug.
final formatErrors = <String>[];

/// The computed text style a node passes to its children, as CSS inherits it.
class _Text {
  _Text({
    required this.color,
    required this.size,
    required this.weight,
    required this.italic,
    required this.family,
    required this.lineHeight,
    required this.letterSpacing,
    required this.align,
    required this.transform,
    required this.nowrap,
    required this.underline,
  });

  int color;
  double size;

  /// The size as code, when it follows the screen (clamp of vw); [size] is
  /// then its value at a desktop's width, for what is measured in em.
  String? sizeCode;

  /// Letter spacing as code, when it follows a size that does.
  String? spacingCode;
  int weight;
  bool italic;
  String? family;

  /// A multiple of the size; null for `normal`.
  double? lineHeight;
  double letterSpacing;
  String? align;
  String? transform;
  bool nowrap;
  bool underline;

  /// Set in the system's monospace (ui-monospace, monospace).
  bool mono = false;

  _Text copy() =>
      _Text(
          color: color,
          size: size,
          weight: weight,
          italic: italic,
          family: family,
          lineHeight: lineHeight,
          letterSpacing: letterSpacing,
          align: align,
          transform: transform,
          nowrap: nowrap,
          underline: underline,
        )
        ..mono = mono
        ..sizeCode = sizeCode
        ..spacingCode = spacingCode;
}

class _FlutterWriter {
  _FlutterWriter(this.plan, this.flavor, this.measure, this.package) {
    for (final s in plan.screens) {
      routes[s.file] = plan.screens.first == s
          ? '/'
          : '/${s.file.replaceAll(RegExp(r'\.html?$'), '')}';
      screenNames[s] = pascal(s.title).isEmpty ? 'Screen' : pascal(s.title);
      _media.addAll(_mediaRules(s.css));
    }
  }

  final DesignPlan plan;
  final FlutterFlavor flavor;
  final bool measure;
  final String package;
  final routes = <String, String>{};
  final screenNames = <DScreen, String>{};
  final assets = <String>{};
  final fonts = <String>{};

  /// An asset's own size in px, from its file, where the export can read it.
  (double, double)? Function(String asset)? imageSize;

  /// The typeface files bundled, for pubspec.yaml.
  List<({String family, int weight, bool italic, String asset, bool opsz})> fontFiles = const [];

  /// Classes switched by width: class -> [(max width, property, value)].
  final _media = <String, List<(double, bool, String, String)>>{};

  // ---- Files ------------------------------------------------------------------

  Map<String, String> files() {
    final out = <String, String>{};
    for (final s in plan.screens) {
      final name = screenNames[s]!;
      final dir = 'lib/ui/${snake(name)}/widgets';
      final parts = plan.parts[s]!;
      for (final p in parts) {
        if (plan.componentOf(p.node) != null) continue;
        out['$dir/${snake(p.name)}.dart'] = _widgetFile(
          p.name,
          p.node,
          from: dir,
          screen: s,
          partsOf: const {},
        );
      }
      out['$dir/${snake(name)}_screen.dart'] = _screenFile(s, name, dir, parts);
    }
    for (final c in plan.components) {
      out['lib/ui/core/widgets/${snake(c.name)}.dart'] = _componentFile(c);
    }
    out['lib/ui/core/design.dart'] = _designFile();
    out['lib/main.dart'] = _main();
    out['pubspec.yaml'] = _pubspec();
    out['analysis_options.yaml'] = 'include: package:flutter_lints/flutter.yaml\n';
    if (measure) out['test/measure_test.dart'] = _measureTest();
    return out;
  }

  String _screenFile(DScreen s, String name, String dir, List<DPart> parts) {
    final ctx = _Ctx(this, from: dir, screen: s, partsOf: {for (final p in parts) p.node: p});
    final body = s.body;
    final text = _rootText();
    final bodyText = _textOf(body, text);
    // A header that sticks to the top as the page scrolls: pinned over it.
    final pinned = stickyHeader(body);
    final children = _flow(body, ctx, bodyText, skip: pinned);
    final bg = _background(body.style);
    final margin = body.style['margin'] ?? '8px';
    final pad = _insets(margin, bodyText.size, ctx);
    final column =
        'Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [${children.join(', ')}])';
    final scroll = pinned == null
        ? 'SingleChildScrollView(child: ${pad == null ? column : 'Padding(padding: $pad, child: $column)'})'
        // Drawn first, it is over the page that scrolls under it.
        : 'CustomScrollView(slivers: [PinnedHeaderSliver(child: ${_element(pinned, ctx, bodyText) ?? 'SizedBox.shrink()'}), '
              'SliverToBoxAdapter(child: ${pad == null ? column : 'Padding(padding: $pad, child: $column)'})])';
    final page =
        'ColoredBox(color: ${bg ?? 'const Color(0xFFFFFFFF)'}, child: '
        'DefaultTextStyle(style: ${_style(bodyText, ctx)}, child: $scroll))';
    return _dart(ctx, [
      '/// ${s.title}: the screen, its parts in order.',
      'class ${name}Screen extends StatelessWidget {',
      '  const ${name}Screen({super.key});',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    return $page;',
      '  }',
      '}',
    ]);
  }

  String _widgetFile(
    String name,
    DNode node, {
    required String from,
    required DScreen screen,
    required Map<DNode, DPart> partsOf,
  }) {
    final ctx = _Ctx(this, from: from, screen: screen, partsOf: partsOf);
    final text = _textOf(node.parent!, _inherited(node.parent!));
    final w = _element(node, ctx, text);
    return _dart(ctx, [
      'class $name extends StatelessWidget {',
      '  const $name({super.key});',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    return ${w ?? 'const SizedBox.shrink()'};',
      '  }',
      '}',
      ...ctx.pieces,
    ]);
  }

  String _componentFile(DComponent c) {
    final screen = plan.screens.firstWhere(
      (s) => c.model.ancestors.lastOrNull == s.body || c.model == s.body,
    );
    final ctx = _Ctx(
      this,
      from: 'lib/ui/core/widgets',
      screen: screen,
      partsOf: const {},
      component: c,
    );
    final text = _textOf(c.model.parent!, _inherited(c.model.parent!));
    final w = _element(c.model, ctx, text, rootOfComponent: true);
    final fields = [
      for (final p in c.params)
        '  final ${p.kind == DParamKind.element ? 'Widget' : 'String'} ${p.name};',
      // Measuring: where this use is in the page, its parts keyed from there.
      if (measure) '  final String at;',
    ];
    final args = [for (final p in c.params) 'required this.${p.name}', if (measure) "this.at = ''"];
    final ctor = args.isEmpty
        ? '  const ${c.name}({super.key});'
        : '  const ${c.name}({super.key, ${args.join(', ')}});';
    return _dart(ctx, [
      '/// Used ${c.uses.length} times${c.params.isEmpty ? ', the same each time' : ''}.',
      'class ${c.name} extends StatelessWidget {',
      ctor,
      if (fields.isNotEmpty) '',
      ...fields,
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    return ${w ?? 'const SizedBox.shrink()'};',
      '  }',
      '}',
      ...ctx.pieces,
    ]);
  }

  String _dart(_Ctx ctx, List<String> body) {
    final imports = <String>{
      "import 'package:flutter/widgets.dart';",
      if (body.any((l) => l.contains('math.'))) "import 'dart:math' as math;",
      if (body.any((l) => l.contains('ui.ImageFilter'))) "import 'dart:ui' as ui;",
      if (body.any((l) => l.contains('TapGestureRecognizer')))
        "import 'package:flutter/gestures.dart';",
      if (body.any((l) => l.contains('SvgPicture')))
        "import 'package:flutter_svg/flutter_svg.dart';",
      if (RegExp(
        r'\b(Design(Colors|Fonts)|vw|vh|ShowWhen|designImage|openLink|Margin|DesignGrid|FlexWrap|PercentWidth|FitContent|CssText|GridTrack|DropShadow)\b',
      ).hasMatch(body.join('\n')))
        "import 'package:$package/ui/core/design.dart';",
      for (final i in ctx.imports) "import 'package:$package/$i';",
    };
    final sorted = imports.toList()..sort((a, b) => _importRank(a).compareTo(_importRank(b)));
    return '${[...sorted, '', '// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables', '', ...body].join('\n')}\n';
  }

  static String _importRank(String i) =>
      i.contains("'dart:") ? '0$i' : (i.contains('package:flutter') ? '1$i' : '2$i');

  // ---- Styles: what CSS computes ----------------------------------------------

  _Text _rootText() => _Text(
    color: 0xFF000000,
    size: 16,
    weight: 400,
    italic: false,
    family: null,
    lineHeight: null,
    letterSpacing: 0,
    align: null,
    transform: null,
    nowrap: false,
    underline: false,
  );

  /// What [n] inherits from everything above it.
  _Text _inherited(DNode n) {
    final chain = n.ancestors.toList().reversed;
    var t = _rootText();
    for (final a in chain) {
      t = _textOf(a, t);
    }
    return t;
  }

  /// [n]'s own text style: [parent]'s, changed by its tag and its style.
  _Text _textOf(DNode n, _Text parent) {
    final t = parent.copy();
    final tag = n.tag ?? '';
    if (_headings[tag] case final scale?) {
      t.size = parent.size * scale;
      t.weight = 700;
    }
    if (tag == 'b' || tag == 'strong') t.weight = 700;
    if (tag == 'i' || tag == 'em') t.italic = true;
    if (tag == 'small') t.size = parent.size * 0.833;
    if (tag == 'code' || tag == 'pre' || tag == 'kbd') t.family = 'monospace';
    if (tag == 'a' && !n.style.containsKey('color')) t.color = 0xFF0000EE;
    if (tag == 'a' && !n.style.containsKey('text-decoration')) t.underline = true;
    final s = n.style;
    if (s['font'] case final f?) _fontShorthand(f, t, parent);
    if (s['font-size'] case final f?) {
      final l = length(f.trim(), fontSize: parent.size);
      if (l != null && l.dynamic) {
        t.sizeCode = l.code;
        t.size = cssPx(f, fontSize: parent.size) ?? t.size;
      } else {
        t.sizeCode = null;
        t.size = _fontSize(f, parent.size) ?? t.size;
      }
      t.spacingCode = null;
    }
    if (s['font-weight'] case final w?) t.weight = _weight(w, parent.weight);
    if (s['font-style'] case final st?) t.italic = st.trim() == 'italic';
    if (s['font-family'] case final fam?) {
      t.family = _family(fam);
      t.mono = _isMono(fam);
    }
    if (s['color'] case final c?) t.color = _color(c) ?? t.color;
    if (s['line-height'] case final lh?) t.lineHeight = _lineHeight(lh, t.size);
    if (s['letter-spacing'] case final ls?) {
      final em = RegExp(r'^(-?[\d.]+)em$').firstMatch(ls.trim());
      t.letterSpacing = ls.trim() == 'normal' ? 0 : (length(ls, fontSize: t.size)?.value ?? 0);
      t.spacingCode = em != null && t.sizeCode != null ? '${em[1]} * (${t.sizeCode})' : null;
    }
    if (s['text-align'] case final a?) t.align = a.trim();
    if (s['text-transform'] case final tr?) t.transform = tr.trim() == 'none' ? null : tr.trim();
    if (s['white-space'] case final ws?) t.nowrap = ws.contains('nowrap');
    if (s['text-decoration'] case final d?) t.underline = d.contains('underline');
    return t;
  }

  static const _headings = {'h1': 2.0, 'h2': 1.5, 'h3': 1.17, 'h4': 1.0, 'h5': 0.83, 'h6': 0.67};

  void _fontShorthand(String f, _Text t, _Text parent) {
    // [style] [weight] size[/line-height] family
    final m = RegExp(
      r'^(?:(italic|normal)\s+)?(?:(\d{3}|bold|normal)\s+)?([\d.]+(?:px|em|rem|%))(?:\s*/\s*([\d.]+(?:px|em|%)?))?\s+(.+)$',
    ).firstMatch(f.trim());
    if (m == null) return;
    if (m[1] != null) t.italic = m[1] == 'italic';
    if (m[2] != null) t.weight = _weight(m[2]!, parent.weight);
    t.size = _fontSize(m[3]!, parent.size) ?? t.size;
    if (m[4] != null) t.lineHeight = _lineHeight(m[4]!, t.size);
    t.family = _family(m[5]!);
    t.mono = _isMono(m[5]!);
  }

  double? _fontSize(String v, double parent) {
    final t = v.trim();
    if (t.endsWith('%')) return parent * double.parse(t.substring(0, t.length - 1)) / 100;
    // A size that follows the screen's width is fixed at the design's own.
    final l = length(t, fontSize: parent);
    return l?.value ?? _atDesignWidth(t, parent);
  }

  /// A clamp of vw at 1440 wide, for text sizes Flutter needs as numbers
  /// in its styles: computed where the style is built (see [_size]).
  double? _atDesignWidth(String t, double parent) => null;

  int _weight(String w, int parent) => switch (w.trim()) {
    'bold' => 700,
    'normal' => 400,
    'bolder' => parent >= 600 ? 900 : 700,
    'lighter' => parent >= 600 ? 400 : 100,
    final n => int.tryParse(n) ?? parent,
  };

  /// A stack that asks for the system's monospace first.
  bool _isMono(String fam) {
    final first = splitTop(fam, ',').first.trim().toLowerCase();
    return first == 'ui-monospace' ||
        first == 'monospace' ||
        first == 'sfmono-regular' ||
        first == 'menlo';
  }

  String? _family(String fam) {
    final first = splitTop(fam, ',').first.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
    const generic = {
      'sans-serif',
      'serif',
      'monospace',
      'system-ui',
      'ui-sans-serif',
      'ui-serif',
      'ui-monospace',
      '-apple-system',
      'blinkmacsystemfont',
      'cursive',
    };
    if (generic.contains(first.toLowerCase())) return null;
    fonts.add(first);
    return first;
  }

  double? _lineHeight(String v, double size) {
    final t = v.trim();
    if (t == 'normal') return null;
    final n = double.tryParse(t);
    if (n != null) return n;
    if (t.endsWith('%')) return double.parse(t.substring(0, t.length - 1)) / 100;
    final l = length(t, fontSize: size);
    return l?.value == null ? null : l!.value! / size;
  }

  int? _color(String v) => colorValue(v.trim().replaceAll('!important', '').trim());

  /// A color, as the theme names it where it does.
  String colorRef(int argb) {
    for (final t in plan.tokens) {
      if (t.kind == DTokenKind.color && colorValue(t.value) == argb) {
        return 'DesignColors.${t.name}';
      }
    }
    return 'const ${colorCode(argb)}';
  }

  String _style(_Text t, _Ctx ctx) {
    final parts = <String>[
      'color: ${colorRef(t.color)}',
      'fontSize: ${t.sizeCode ?? num(t.size)}',
      if (t.weight != 400) 'fontWeight: FontWeight.w${t.weight}',
      if (t.italic) 'fontStyle: FontStyle.italic',
      if (t.family != null) 'fontFamily: ${_familyRef(t.family!)}',
      if (t.family == null && t.mono) "fontFamilyFallback: const ['SF Mono', 'Menlo', 'monospace']",
      // A variable font: its weight, and its optical size as the page sets it
      // (font-optical-sizing: auto, the size in px).
      if (t.family != null && fontFiles.any((f) => f.family == t.family && f.opsz))
        'fontVariations: [FontVariation(\'wght\', ${t.weight}), FontVariation(\'opsz\', ${t.sizeCode ?? num(t.size)})]',
      if (t.lineHeight != null) 'height: ${num(t.lineHeight!)}',
      if (t.lineHeight != null) 'leadingDistribution: TextLeadingDistribution.even',
      if (t.spacingCode != null)
        'letterSpacing: ${t.spacingCode}'
      else if (t.letterSpacing != 0)
        'letterSpacing: ${num(t.letterSpacing)}',
      if (t.underline) 'decoration: TextDecoration.underline',
      if (t.underline) 'decorationColor: ${colorRef(t.color)}',
    ];
    return 'TextStyle(${parts.join(', ')})';
  }

  String _familyRef(String family) {
    for (final t in plan.tokens) {
      if (t.kind == DTokenKind.font && _family(t.value) == family) return 'DesignFonts.${t.name}';
    }
    return jsonEncode(family);
  }

  String? _background(Map<String, String> s) {
    final bg = s['background-color'] ?? s['background'];
    if (bg == null) return null;
    final c = _color(bg);
    return c == null ? null : colorRef(c);
  }

  // ---- Boxes ------------------------------------------------------------------

  String _display(DNode n) {
    final d = n.style['display']?.replaceAll('!important', '').trim();
    if (d != null) return d;
    return _blockTags.contains(n.tag) ? 'block' : 'inline';
  }

  static const _blockTags = {
    'address', 'article', 'aside', 'blockquote', 'body', 'dd', 'div', 'dl', 'dt', 'fieldset', //
    'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr',
    'li', 'main', 'nav', 'ol', 'p', 'pre', 'section', 'summary', 'table', 'ul',
  };

  /// Whether [n] is as wide as its line, as a block in flow is, or an item
  /// a flex column stretches.
  bool _fillsLine(DNode n) {
    if (!_isBlock(n)) return false;
    final p = n.parent;
    if (p == null) return true;
    final d = _display(p);
    if (!d.contains('flex') && !d.contains('grid')) return true;
    final column = (p.style['flex-direction'] ?? 'row').startsWith('column');
    final align = n.style['align-self'] ?? p.style['align-items'] ?? 'stretch';
    return d.contains('flex') && column && (align == 'stretch' || align == 'normal');
  }

  bool _isBlock(DNode n) {
    if (n.isText) return false;
    final pos = n.style['position'];
    if (pos == 'absolute' || pos == 'fixed') return false;
    final d = _display(n);
    return d == 'block' || d == 'flex' || d == 'grid' || d == 'list-item' || d == '-webkit-box';
  }

  /// An inline element that is a box of its own (a badge, an icon, a
  /// button): drawn as a widget in the line, not as a run of text.
  bool _isAtom(DNode n) {
    if (n.isText) return false;
    final d = _display(n);
    if (d == 'inline-block' || d == 'inline-flex' || d == 'inline-grid') return true;
    if (n.tag == 'img' || n.tag == 'svg' || n.tag == 'button' || n.tag == 'input') return true;
    final s = n.style;
    return s.keys.any(
      (k) =>
          k.startsWith('padding') ||
          k.startsWith('border') ||
          k.startsWith('background') ||
          k == 'width' ||
          k == 'height',
    );
  }

  bool _absolute(DNode n) => n.style['position'] == 'absolute' || n.style['position'] == 'fixed';

  /// Block flow: [n]'s children top to bottom, runs of inline content as
  /// text, the vertical margins between blocks collapsed as CSS does.
  /// Whether a margin on [side] of [n]'s first (top) or last (bottom) child
  /// goes through it, as CSS collapses it with [n]'s own when nothing is
  /// between them: [n] a block in flow, with no padding, border or
  /// clipping on that side (and no height set, at the bottom).
  bool _passes(DNode n, String side) {
    final p = n.parent;
    if (p == null) return false;
    if (n.tag == 'body' || n.tag == 'html') return false;
    final d = _display(n);
    if (d != 'block' && d != 'list-item') return false;
    final pd = _display(p);
    if (pd.contains('flex') || pd.contains('grid')) return false;
    final s = n.style;
    if ((s['overflow'] ?? s['overflow-y'] ?? 'visible') != 'visible') return false;
    if (s['position'] == 'absolute' || s['position'] == 'fixed' || s['float'] != null) return false;
    final i = side == 'top' ? 0 : 2;
    bool none(String? v) => v == null || (length(v)?.value ?? 1) == 0 || v.trim() == 'none';
    if (!none(s['padding-$side'] ?? (s['padding'] == null ? null : sides(s['padding']!)[i]))) {
      return false;
    }
    final border = s['border-$side'] ?? s['border'];
    if (border != null && !border.contains('none') && border.trim() != '0') return false;
    if (side == 'bottom' && (s['height'] != null || s['min-height'] != null)) return false;
    return true;
  }

  /// [n]'s first or last child in flow, when it is a block: what a margin
  /// can pass through to.
  DNode? _edgeBlock(DNode n, {required bool first}) {
    final kids = [
      for (final c in n.children)
        if (c.isText ? c.text!.trim().isNotEmpty : !_absolute(c) && !_hidden(c)) c,
    ];
    if (kids.isEmpty) return null;
    final c = first ? kids.first : kids.last;
    return _isBlock(c) ? c : null;
  }

  /// [n]'s top and bottom margins with those of its first and last children
  /// that pass through it.
  (DLen, DLen) _outerMargins(DNode n, _Text text) {
    final own = _verticalMargins(n, _textOf(n, text));
    var top = own.$1, bottom = own.$2;
    if (_passes(n, 'top')) {
      if (_edgeBlock(n, first: true) case final c?) {
        top = _collapse(top, _outerMargins(c, _textOf(n, text)).$1);
      }
    }
    if (_passes(n, 'bottom')) {
      if (_edgeBlock(n, first: false) case final c?) {
        bottom = _collapse(bottom, _outerMargins(c, _textOf(n, text)).$2);
      }
    }
    return (top, bottom);
  }

  List<String> _flow(DNode n, _Ctx ctx, _Text text, {DNode? skip}) {
    final out = <String>[];
    DLen? lastBottom;
    // Margins that went through [n] to its parent are not kept in it too.
    final firstOut = _passes(n, 'top') ? _edgeBlock(n, first: true) : null;
    final lastOut = _passes(n, 'bottom') ? _edgeBlock(n, first: false) : null;
    final run = <DNode>[];
    void flushRun() {
      if (run.isEmpty) return;
      final rich = _inline(run, ctx, text, n);
      run.clear();
      if (rich == null) return;
      if (lastBottom != null && _positive(lastBottom!)) {
        out.add('SizedBox(height: ${lastBottom!.code})');
      }
      lastBottom = DLen.px(0);
      out.add(rich);
    }

    for (final c in n.children) {
      if (identical(c, skip)) continue;
      if (!c.isText && _absolute(c)) continue;
      if (!c.isText && _hidden(c)) continue;
      if (_isBlock(c)) {
        flushRun();
        final m = _outerMargins(c, text);
        final gap = lastBottom == null
            ? (identical(c, firstOut) ? DLen.px(0) : m.$1)
            : _collapse(lastBottom!, m.$1);
        final w = _element(c, ctx, text);
        if (w == null) continue;
        // A negative margin pulls it up over what is before it.
        final pull = gap.value != null && gap.value! < 0;
        final item = pull ? 'Margin(top: ${gap.code}, child: $w)' : w;
        final space = _positive(gap) ? 'SizedBox(height: ${gap.code})' : null;
        // Hidden at a width, it is gone with the space before it.
        if (_shownIf(c) case final shown?) {
          out.add('if ($shown) ...[${[?space, item].join(', ')}]');
        } else {
          if (space != null) out.add(space);
          out.add(item);
        }
        lastBottom = identical(c, lastOut) ? DLen.px(0) : m.$2;
      } else {
        run.add(c);
      }
    }
    flushRun();
    if (lastBottom != null && _positive(lastBottom!)) {
      out.add('SizedBox(height: ${lastBottom!.code})');
    }
    return out;
  }

  /// Whether [l] takes room: a px value above 0, or one that follows the
  /// screen (never below 0 in the subset: a clamp of positive lengths).
  bool _positive(DLen l) => l.value == null ? !l.code.startsWith('-') : l.value! > 0;

  /// Two margins that meet, as one: the larger, or for negatives their
  /// sum, as CSS collapses them. One that follows the screen is taken as
  /// positive.
  DLen _collapse(DLen a, DLen b) {
    if (a.value != null && b.value != null) {
      final x = a.value!, y = b.value!;
      if (x >= 0 && y >= 0) return DLen.px(x > y ? x : y);
      if (x < 0 && y < 0) return DLen.px(x < y ? x : y);
      return DLen.px(x + y);
    }
    if (a.isZero) return b;
    if (b.isZero) return a;
    return DLen('math.max(${a.code}, ${b.code})', dynamic: true);
  }

  bool _hidden(DNode n) => _display(n) == 'none';

  /// Top and bottom margins (auto as 0), from the style or the tag's own (a
  /// heading's, a paragraph's): px, or code that follows the screen.
  (DLen, DLen) _verticalMargins(DNode n, _Text own) {
    final s = n.style;
    final zero = DLen.px(0);
    DLen? top, bottom;
    if (s['margin'] case final m?) {
      final v = sides(m);
      top = length(v[0], fontSize: own.size) ?? zero;
      bottom = length(v[2], fontSize: own.size) ?? zero;
    } else if (_tagMargins[n.tag] case final em?) {
      top = DLen.px(em * own.size);
      bottom = DLen.px(em * own.size);
    }
    if (s['margin-top'] case final t?) top = length(t, fontSize: own.size) ?? zero;
    if (s['margin-bottom'] case final b?) bottom = length(b, fontSize: own.size) ?? zero;
    return (top ?? zero, bottom ?? zero);
  }

  /// [w] with its top and bottom margins as padding, kept as they are.
  String _keepMargins((DLen, DLen) m, String w) {
    if (m.$1.isZero && m.$2.isZero) return w;
    final sides = [if (!m.$1.isZero) 'top: ${m.$1.code}', if (!m.$2.isZero) 'bottom: ${m.$2.code}'];
    return 'Padding(padding: EdgeInsets.only(${sides.join(', ')}), child: $w)';
  }

  static const _tagMargins = {
    'p': 1.0, 'h1': 0.67, 'h2': 0.83, 'h3': 1.0, 'h4': 1.33, 'h5': 1.67, 'h6': 2.33, //
    'ul': 1.0, 'ol': 1.0, 'blockquote': 1.0, 'figure': 1.0, 'dl': 1.0, 'pre': 1.0, 'hr': 0.5,
  };

  /// A run of text and inline elements as one Text.rich, its spaces
  /// collapsed as the page collapses them; null when it is only space.
  /// The last text in [run] that has more than space in it, when nothing
  /// drawn (a badge, an image, a break) comes after it; null otherwise.
  DNode? _lastText(List<DNode> run) {
    DNode? last;
    void walk(DNode n) {
      if (n.isText) {
        if (n.text!.trim().isNotEmpty) last = n;
        return;
      }
      if (_hidden(n) || _absolute(n)) return;
      if (_isAtom(n) || n.tag == 'br') {
        last = null;
        return;
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    for (final n in run) {
      walk(n);
    }
    return last;
  }

  String? _inline(List<DNode> run, _Ctx ctx, _Text text, DNode container) {
    final spans = <String>[];
    var lastSpace = true; // a line starts without leading space
    final end = _lastText(run);
    void walk(DNode n, _Text t, String? href) {
      if (n.isText) {
        var s = n.text!;
        if (!t.nowrap || true) {
          s = s.replaceAll(RegExp(r'\s+'), ' ');
          if (lastSpace && s.startsWith(' ')) s = s.substring(1);
          // Nor is space at the end of the last line drawn.
          if (identical(n, end)) s = s.trimRight();
        }
        if (s.isEmpty) return;
        lastSpace = s.endsWith(' ');
        final param = ctx.paramAt(n, DParamKind.text);
        // A component's text comes in as it is written: cased here, as the
        // page cases it (text-transform), like text written in place.
        final value = param != null
            ? switch (t.transform) {
                'uppercase' => '${param.name}.toUpperCase()',
                'lowercase' => '${param.name}.toLowerCase()',
                'capitalize' =>
                  "${param.name}.replaceAllMapped(RegExp(r'\\b\\w'), (m) => m[0]!.toUpperCase())",
                _ => param.name,
              }
            : jsonEncode(_transformed(s, t.transform));
        spans.add(_span(value, t, text, ctx, href: href, trimEnd: false));
        return;
      }
      if (_hidden(n) || _absolute(n)) return;
      if (_isAtom(n)) {
        final w = _element(n, ctx, t);
        if (w != null) {
          final linked = href == null ? w : _link(href, w, ctx, n);
          spans.add(
            'WidgetSpan(alignment: PlaceholderAlignment.${_atomAlign(n)}, baseline: TextBaseline.alphabetic, child: $linked)',
          );
          lastSpace = false;
        }
        return;
      }
      if (n.tag == 'br') {
        spans.add("TextSpan(text: '\\n')");
        lastSpace = true;
        return;
      }
      final own = _textOf(n, t);
      final link = n.tag == 'a'
          ? (ctx.paramAt(n, DParamKind.attr, 'href')?.name ?? _quoted(n.attrs['href']))
          : href;
      for (final c in n.children) {
        walk(c, own, link);
      }
    }

    for (final n in run) {
      walk(n, text, null);
    }
    // Space at the end of a line is not drawn either.
    while (spans.isNotEmpty && spans.last.endsWith("' '))")) {
      spans.removeLast();
    }
    if (spans.isEmpty) return null;
    final align = _textAlign(text.align);
    final props = [if (align != null) 'textAlign: $align', if (text.nowrap) 'softWrap: false'];
    final span = 'TextSpan(style: ${_style(text, ctx)}, children: [${spans.join(', ')}])';
    final rest = props.isEmpty ? '' : ', ${props.join(', ')}';
    // CssText places each line where the page does; it draws text only, so
    // a run with a widget in it, or justified, stays a Text.rich.
    final exact = !spans.any((x) => x.startsWith('WidgetSpan(')) && align != 'TextAlign.justify';
    return exact ? 'CssText($span$rest)' : 'Text.rich($span$rest)';
  }

  String _atomAlign(DNode n) {
    final va = n.style['vertical-align'];
    if (va == 'middle') return 'middle';
    if (va == 'top') return 'top';
    if (va == 'bottom') return 'bottom';
    return n.tag == 'img' || n.tag == 'svg' ? 'bottom' : 'baseline';
  }

  String? _quoted(String? s) => s == null ? null : jsonEncode(s);

  String _span(String text, _Text t, _Text base, _Ctx ctx, {String? href, required bool trimEnd}) {
    final style = _same(t, base) ? '' : ', style: ${_style(t, ctx)}';
    if (href == null) return 'TextSpan(text: $text$style)';
    ctx.usesGestures = true;
    return 'TextSpan(text: $text$style, mouseCursor: SystemMouseCursors.click, '
        'recognizer: TapGestureRecognizer()..onTap = () => openLink(context, $href))';
  }

  bool _same(_Text a, _Text b) =>
      a.color == b.color &&
      a.size == b.size &&
      a.sizeCode == b.sizeCode &&
      a.weight == b.weight &&
      a.italic == b.italic &&
      a.family == b.family &&
      a.lineHeight == b.lineHeight &&
      a.letterSpacing == b.letterSpacing &&
      a.underline == b.underline;

  String _transformed(String s, String? transform) => switch (transform) {
    'uppercase' => s.toUpperCase(),
    'lowercase' => s.toLowerCase(),
    'capitalize' => s.replaceAllMapped(RegExp(r'\b\w'), (m) => m[0]!.toUpperCase()),
    _ => s,
  };

  String? _textAlign(String? a) => switch (a) {
    'center' => 'TextAlign.center',
    'right' || 'end' => 'TextAlign.right',
    'justify' => 'TextAlign.justify',
    _ => null,
  };

  /// [n] as a widget, laid out as its display says and boxed as its style
  /// says: null when nothing of it shows.
  String? _element(DNode n, _Ctx ctx, _Text parentText, {bool rootOfComponent = false}) {
    if (n.isText) return _inline([n], ctx, parentText, n.parent ?? n);
    if (_hidden(n)) return null;
    // A part of the screen, a component's use, a parameter: by name.
    if (ctx.partsOf[n] case final part?) {
      final c = plan.componentOf(n);
      if (c != null) return _use(c, n, ctx);
      ctx.imports.add('ui/${snake(screenNames[part.screen]!)}/widgets/${snake(part.name)}.dart');
      return '${part.name}()';
    }
    if (!rootOfComponent) {
      final c = plan.componentOf(n);
      if (c != null && c != ctx.component) return _use(c, n, ctx);
    }
    if (ctx.paramAt(n, DParamKind.element) case final p?) return p.name;

    final text = _textOf(n, parentText);
    final display = _display(n);
    String? child;
    switch (n.tag) {
      case 'img':
        child = _image(n, ctx);
      case 'svg':
        child = _svg(n, ctx, text);
      case 'hr':
        child = 'SizedBox(height: 0)';
      case 'input' || 'textarea' || 'select':
        child = _inline(const [], ctx, text, n) ?? 'SizedBox(height: ${num(text.size * 1.2)})';
      default:
        if (display.contains('flex')) {
          child = _flex(n, ctx, text);
        } else if (display.contains('grid')) {
          child = _grid(n, ctx, text);
        } else {
          final flow = _flow(n, ctx, text);
          child = switch (flow.length) {
            0 => null,
            1 when !flow.single.startsWith('if (') => flow.single,
            _ =>
              'Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [${flow.join(', ')}])',
          };
        }
    }
    // Layers: its absolute children over its flow.
    final layers = [
      for (final c in n.children)
        if (!c.isText && _absolute(c) && !_hidden(c)) c,
    ];
    final positioned = [
      for (final l in layers)
        if (_element(l, ctx, text) case final w?) _positioned(l, w, text),
    ];
    // Its own text style for what is inside, when it changes it.
    if (child != null && !_same(text, parentText) && !_simpleText(child)) {
      child = 'DefaultTextStyle(style: ${_style(text, ctx)}, child: $child)';
    }
    var w = _box(n, child, ctx, text, layers: positioned);
    if (n.tag == 'a' || n.tag == 'button') {
      final href = n.tag == 'a'
          ? (ctx.paramAt(n, DParamKind.attr, 'href')?.name ?? _quoted(n.attrs['href']))
          : null;
      w = _link(href, w, ctx, n);
    }
    return w;
  }

  bool _simpleText(String child) => child.startsWith('Text.rich(') || child.startsWith('CssText(');

  String _image(DNode n, _Ctx ctx) {
    final src = n.attrs['src'] ?? '';
    final param = ctx.paramAt(n, DParamKind.attr, 'src');
    final w = double.tryParse(n.attrs['width'] ?? '');
    final h = double.tryParse(n.attrs['height'] ?? '');
    final fit = switch (n.style['object-fit']) {
      'contain' => 'BoxFit.contain',
      'fill' => 'BoxFit.fill',
      'none' => 'BoxFit.none',
      'scale-down' => 'BoxFit.scaleDown',
      _ => 'BoxFit.cover',
    };
    // No size anywhere: as large as the file is, as the page draws it.
    bool unset(String? v) => v == null || v.trim() == 'auto';
    final natural = w == null && h == null && unset(n.style['width']) && unset(n.style['height']);
    final size = [
      if (w != null) 'width: ${num(w)}',
      if (h != null) 'height: ${num(h)}',
      if (natural) 'natural: true',
    ].join(', ');
    final extra = size.isEmpty ? '' : ', $size';
    if (param != null) return 'designImage(${param.name}, fit: $fit$extra)';
    if (!src.contains(':') && src.isNotEmpty) assets.add(src.replaceFirst(RegExp(r'^\./'), ''));
    return 'designImage(${jsonEncode(src.contains(':') ? src : 'assets/${src.replaceFirst(RegExp(r'^\./'), '')}')}, fit: $fit$extra)';
  }

  String _svg(DNode n, _Ctx ctx, _Text text) {
    ctx.usesSvg = true;
    final markup = _markup(n, text.color);
    final w = double.tryParse(n.attrs['width'] ?? '') ?? length(n.style['width'] ?? '')?.value;
    final h = double.tryParse(n.attrs['height'] ?? '') ?? length(n.style['height'] ?? '')?.value;
    return "SvgPicture.string(${_raw(markup)}${w == null ? '' : ', width: ${num(w)}'}${h == null ? '' : ', height: ${num(h)}'})";
  }

  /// An SVG's markup, `currentColor` as the color it has there.
  String _markup(DNode n, int color) {
    if (n.isText) return const HtmlEscape(HtmlEscapeMode.element).convert(n.text!);
    final hex = '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final attrs = [
      for (final e in n.attrs.entries) '${e.key}="${e.value.replaceAll('currentColor', hex)}"',
      if (n.tag == 'svg' && !n.attrs.containsKey('xmlns')) 'xmlns="http://www.w3.org/2000/svg"',
    ];
    if (n.style.isNotEmpty) {
      attrs.add(
        'style="${n.style.entries.map((e) => '${e.key}:${e.value}').join(';').replaceAll('currentColor', hex)}"',
      );
    }
    return '<${n.tag}${attrs.isEmpty ? '' : ' ${attrs.join(' ')}'}>${n.children.map((c) => _markup(c, color)).join()}</${n.tag}>';
  }

  String _raw(String s) => s.contains("'''") ? jsonEncode(s) : "r'''$s'''";

  String _positioned(DNode l, String child, _Text text) {
    var w = child;
    final s = l.style;
    final v = <String, String>{};
    if (s['inset'] case final i?) {
      final p = sides(i);
      for (final (k, x) in [('top', p[0]), ('right', p[1]), ('bottom', p[2]), ('left', p[3])]) {
        if (length(x, fontSize: text.size) case final d?) v[k] = d.code;
      }
    }
    for (final k in ['top', 'right', 'bottom', 'left', 'width', 'height']) {
      if (s[k] case final x?) {
        if (length(x, fontSize: text.size) case final d?) {
          v[k] = d.code;
        } else if (RegExp(r'^-?[\d.]+%$').hasMatch(x.trim()) &&
            (k == 'left' || k == 'right' || k == 'width')) {
          // A share of the box's width, as the page has it.
          v[k] = 'box.maxWidth * ${num(double.parse(x.trim().replaceAll('%', '')) / 100)}';
        }
      }
    }
    // No insets on an axis: where it would be in flow. In a flex or grid
    // box that is where the box aligns its items (place-items: center).
    final (ax, ay) = _staticAlign(l);
    final x = !v.containsKey('left') && !v.containsKey('right') ? ax : null;
    final y = !v.containsKey('top') && !v.containsKey('bottom') ? ay : null;
    if ((x ?? -1) != -1 || (y ?? -1) != -1) {
      // Its own box sizes it then (its width, a share of the box's).
      if (x != null) {
        v
          ..remove('width')
          ..['left'] = '0'
          ..['right'] = '0';
      }
      if (y != null) {
        v
          ..remove('height')
          ..['top'] = '0'
          ..['bottom'] = '0';
      }
      // Aligned both ways it may be larger than the box and still centered,
      // as the page draws it: past the box, not squeezed into it.
      w = x != null && y != null
          ? 'OverflowBox(alignment: Alignment($x, $y), minWidth: 0, minHeight: 0, maxHeight: double.infinity, child: $w)'
          : 'Align(alignment: Alignment(${x ?? -1}, ${y ?? -1}), child: $w)';
    }
    return 'Positioned(${[for (final e in v.entries) '${e.key}: ${e.value}'].join(', ')}${v.isEmpty ? '' : ', '}child: $w)';
  }

  /// Where a flex or grid box would put [l] without insets, across and down:
  /// -1 at the start, 0 centered, 1 at the end.
  (int, int) _staticAlign(DNode l) {
    final p = l.parent;
    if (p == null) return (-1, -1);
    final d = _display(p);
    final ps = p.style;
    int at(String? v) => switch (v?.trim()) {
      'center' => 0,
      'end' || 'flex-end' || 'right' || 'bottom' => 1,
      _ => -1,
    };
    if (d.contains('grid')) {
      final place = ps['place-items'] == null ? null : splitTop(ps['place-items']!, ' ');
      final down = l.style['align-self'] ?? ps['align-items'] ?? place?.first;
      final across = l.style['justify-self'] ?? ps['justify-items'] ?? place?.last;
      return (at(across), at(down));
    }
    if (d.contains('flex')) {
      final column = (ps['flex-direction'] ?? 'row').startsWith('column');
      final main = at(ps['justify-content']),
          cross = at(l.style['align-self'] ?? ps['align-items']);
      return column ? (cross, main) : (main, cross);
    }
    return (-1, -1);
  }

  /// [child] boxed as [n]'s style says: padding, background, border,
  /// corners, shadow, size, clipping, opacity, transform.
  String _box(DNode n, String? child, _Ctx ctx, _Text text, {List<String> layers = const []}) {
    final s = n.style;
    final fs = text.size;
    final pad = _insets(
      s['padding'],
      fs,
      ctx,
      top: s['padding-top'],
      right: s['padding-right'],
      bottom: s['padding-bottom'],
      left: s['padding-left'],
    );
    final deco = <String>[];
    final bg = s['background'] ?? s['background-color'];
    if (bg != null) {
      final g = gradient(bg.trim(), colorRef);
      final c = g == null ? _color(bg) : null;
      if (g != null) deco.add('gradient: $g');
      if (c != null && c != 0) deco.add('color: ${colorRef(c)}');
    }
    final current = colorRef(text.color);
    final border = <String, String>{};
    if (s['border'] case final b?) {
      final side = borderSide(b, colorRef, current: current);
      if (side != null && side != 'BorderSide.none') border['all'] = side;
    }
    for (final side in ['top', 'right', 'bottom', 'left']) {
      if (s['border-$side'] case final b?) {
        final bs = borderSide(b, colorRef, current: current);
        if (bs != null) border[side] = bs;
      }
    }
    if (border.isNotEmpty) {
      if (border.length == 1 && border.containsKey('all')) {
        deco.add('border: Border.fromBorderSide(${border['all']})');
      } else {
        final all = border['all'];
        String sideOf(String k) => border[k] ?? all ?? 'BorderSide.none';
        deco.add(
          'border: Border(top: ${sideOf('top')}, right: ${sideOf('right')}, bottom: ${sideOf('bottom')}, left: ${sideOf('left')})',
        );
      }
    }
    if (s['border-radius'] case final r?) {
      final l = length(splitTop(r, ' ').first, fontSize: fs);
      if (l != null) deco.add('borderRadius: BorderRadius.circular(${l.code})');
    }
    if (s['box-shadow'] case final sh?) {
      final list = shadows(sh, colorRef);
      if (list != null) deco.add('boxShadow: $list');
    }
    final clip = (s['overflow'] ?? s['overflow-x'] ?? s['overflow-y']) == 'hidden';
    String w = child ?? 'SizedBox.shrink()';
    final boxSizing = s['box-sizing'] == 'border-box';
    final size = _constraints(n, fs, ctx);
    // A block with a max-width and no width fills its line up to it: Flutter
    // would let it shrink to its content once it is aligned.
    if (size != null && size.contains('maxWidth') && s['width'] == null && _fillsLine(n)) {
      w = 'SizedBox(width: double.infinity, child: $w)';
    }
    // Layers sit against the padding's outer edge, as CSS places them: the
    // padding goes inside the stack, under them.
    if (layers.isNotEmpty) {
      final flow = pad == null ? w : 'Padding(padding: $pad, child: $w)';
      final stack = 'Stack(clipBehavior: Clip.none, children: [$flow, ${layers.join(', ')}])';
      w = layers.any((p) => p.contains('box.maxWidth'))
          ? 'LayoutBuilder(builder: (context, box) => $stack)'
          : stack;
    }
    final container = <String>[
      if (pad != null && layers.isEmpty) 'padding: $pad',
      if (deco.isNotEmpty) 'decoration: BoxDecoration(${deco.join(', ')})',
      if (clip && deco.isNotEmpty) 'clipBehavior: Clip.antiAlias',
    ];
    if (size != null && !boxSizing && container.isNotEmpty) {
      // Its width and height are its content's (content-box): sized inside.
      w = 'ConstrainedBox(constraints: $size, child: $w)';
    }
    if (container.isNotEmpty) w = 'Container(${container.join(', ')}, child: $w)';
    if (size != null && (boxSizing || container.isEmpty)) {
      w = 'ConstrainedBox(constraints: $size, child: $w)';
    }
    if (clip && deco.isEmpty) w = 'ClipRect(child: $w)';
    // Its height from its width, so inside what sets the width.
    if (s['aspect-ratio'] case final ar?) {
      final p = ar.split('/').map((x) => double.tryParse(x.trim())).toList();
      final ratio = p.length == 2 && p[0] != null && p[1] != null ? p[0]! / p[1]! : p[0];
      if (ratio != null) w = 'AspectRatio(aspectRatio: ${num(ratio)}, child: $w)';
    }
    // Widths that are a share of the line's (80%, min(300px, 80%)).
    final percent = _percentWidth(n, fs, w, extra: boxSizing ? 0 : _sideRoom(s, fs));
    if (percent != null) w = percent;
    // Measured here: the box itself, inside its margins and alignment.
    if (measure) w = 'KeyedSubtree(key: ${_measureKey(n, ctx)}, child: $w)';
    // As wide as its content (fit-content, max-content), at the line's start.
    if (const {'fit-content', 'max-content', 'min-content'}.contains(s['width']?.trim())) {
      w = 'Align(alignment: Alignment.topLeft, widthFactor: 1, child: IntrinsicWidth(child: $w))';
    }
    if (s['backdrop-filter'] ?? s['-webkit-backdrop-filter'] case final f?) {
      // Its functions in order, each over the last: blur(24px) saturate(140%)
      // blurs what is behind, then saturates that.
      String? filter;
      for (final (name, arg) in _filterFunctions(f)) {
        final next = name == 'blur'
            ? switch (length(arg.isEmpty ? '0' : arg)?.value ?? 0) {
                final r when r > 0 => 'ui.ImageFilter.blur(sigmaX: ${num(r)}, sigmaY: ${num(r)})',
                _ => null,
              }
            : switch (_colorMatrix(name, arg)) {
                final m? => 'ColorFilter.matrix(<double>[${m.map(num).join(', ')}])',
                null => null,
              };
        if (next == null) continue;
        filter = filter == null ? next : 'ui.ImageFilter.compose(outer: $next, inner: $filter)';
      }
      if (filter != null) {
        ctx.usesUi = true;
        w = 'ClipRect(child: BackdropFilter(filter: $filter, child: $w))';
      }
    }
    if (s['filter'] case final f?) w = _filter(f, w, ctx);
    if (s['opacity'] case final o?) {
      final v = double.tryParse(o.trim());
      if (v != null && v < 1) w = 'Opacity(opacity: ${num(v)}, child: $w)';
    }
    if (s['transform'] case final t?) w = _transform(t, w, fs);
    if (s['position'] == 'relative') {
      final dx =
          length(s['left'] ?? '', fontSize: fs)?.code ??
          (length(s['right'] ?? '', fontSize: fs) == null
              ? null
              : '-${length(s['right']!, fontSize: fs)!.code}');
      final dy =
          length(s['top'] ?? '', fontSize: fs)?.code ??
          (length(s['bottom'] ?? '', fontSize: fs) == null
              ? null
              : '-${length(s['bottom']!, fontSize: fs)!.code}');
      if (dx != null || dy != null) {
        w = 'Transform.translate(offset: Offset(${dx ?? '0'}, ${dy ?? '0'}), child: $w)';
      }
    }
    // A box narrower than its line (its own width or max-width; min-width
    // never narrows it) sits at the
    // line's start, as a block does: Flutter would stretch it otherwise.
    final ownWidth = percent != null || (size?.contains('maxWidth') ?? false);
    final m0 = s['margin'] == null ? null : sides(s['margin']!);
    final autoMargin =
        (s['margin-left'] ?? m0?[3]) == 'auto' || (s['margin-right'] ?? m0?[1]) == 'auto';
    if (ownWidth && !autoMargin && _isBlock(n)) {
      w = 'Align(alignment: Alignment.topLeft, widthFactor: 1, child: $w)';
    }
    // Centered by auto margins, at its max width.
    final m = s['margin'] == null ? null : sides(s['margin']!);
    final ml = s['margin-left'] ?? m?[3], mr = s['margin-right'] ?? m?[1];
    if (ml == 'auto' || mr == 'auto') {
      final align = ml == 'auto' && mr == 'auto'
          ? 'Alignment.topCenter'
          : (ml == 'auto' ? 'Alignment.topRight' : 'Alignment.topLeft');
      w = 'Align(alignment: $align, child: $w)';
    }
    // Side margins (top and bottom are the flow's, collapsed there).
    final l = _len(ml, fs), r = _len(mr, fs);
    if ((l != null && !l.isZero) || (r != null && !r.isZero)) {
      w = 'Padding(padding: EdgeInsets.only(${[if (l != null && !l.isZero) 'left: ${l.code}', if (r != null && !r.isZero) 'right: ${r.code}'].join(', ')}), child: $w)';
    }
    return w;
  }

  DLen? _len(String? v, double fs) => v == null ? null : length(v, fontSize: fs);

  /// [child] in a [PercentWidth], when its width or limits are a share of
  /// the line's; null when none is. [extra] is its padding and border, for a
  /// content-box width.
  String? _percentWidth(DNode n, double fs, String child, {double extra = 0}) {
    final s = n.style;
    final args = <String>[];
    for (final (key, name) in [
      ('width', 'width'),
      ('min-width', 'minWidth'),
      ('max-width', 'maxWidth'),
    ]) {
      final v = s[key];
      if (v == null || !hasPercent(v)) continue;
      final l = length(v, fontSize: fs, percentOf: 'b');
      if (l == null || l.code.contains('context')) continue;
      final plus = extra == 0 || key != 'width' ? '' : ' + ${num(extra)}';
      args.add('$name: (b) => ${l.code}$plus');
    }
    if (args.isEmpty) return null;
    return 'PercentWidth(${args.join(', ')}, child: $child)';
  }

  /// Its padding and border across, in px, where they are known.
  double _sideRoom(Map<String, String> s, double fs) {
    double side(String? v) => v == null ? 0 : (length(v, fontSize: fs)?.value ?? 0);
    final pad = s['padding'] == null ? null : sides(s['padding']!);
    double border(String? v) {
      if (v == null) return 0;
      for (final part in splitTop(v, ' ')) {
        if (length(part, fontSize: fs)?.value case final x?) return x;
      }
      return 0;
    }

    return side(s['padding-left'] ?? pad?[3]) +
        side(s['padding-right'] ?? pad?[1]) +
        border(s['border-left'] ?? s['border']) +
        border(s['border-right'] ?? s['border']);
  }

  /// The functions of a CSS filter, in order: (name, its argument).
  List<(String, String)> _filterFunctions(String f) => [
    for (final m in RegExp(r'([a-z-]+)\(((?:[^()]|\([^()]*\))*)\)').allMatches(f))
      if (!const {'rgb', 'rgba', 'hsl', 'hsla', 'var', 'calc'}.contains(m[1]))
        (m[1]!, m[2]!.trim()),
  ];

  /// The 4x5 color matrix (Flutter's, offsets in 0..255) of a CSS filter
  /// function, as the Filter Effects spec gives it, in sRGB as the page draws
  /// it; null for blur, drop-shadow and what is not a color change.
  List<double>? _colorMatrix(String name, String arg) {
    double amount({double whole = 1}) {
      final t = arg.trim();
      if (t.isEmpty) return whole;
      if (t.endsWith('%')) return (double.tryParse(t.substring(0, t.length - 1)) ?? 100) / 100;
      return double.tryParse(t) ?? whole;
    }

    List<double> m(List<double> rgb, {double o = 0, double alpha = 1}) => [
      for (var r = 0; r < 3; r++) ...[rgb[r * 3], rgb[r * 3 + 1], rgb[r * 3 + 2], 0.0, o * 255],
      0.0,
      0.0,
      0.0,
      alpha,
      0.0,
    ];
    switch (name) {
      case 'brightness':
        final a = amount();
        return m([a, 0, 0, 0, a, 0, 0, 0, a]);
      case 'contrast':
        final a = amount();
        return m([a, 0, 0, 0, a, 0, 0, 0, a], o: 0.5 - 0.5 * a);
      case 'invert':
        final a = amount().clamp(0.0, 1.0);
        final k = 1 - 2 * a;
        return m([k, 0, 0, 0, k, 0, 0, 0, k], o: a);
      case 'opacity':
        return m([1, 0, 0, 0, 1, 0, 0, 0, 1], alpha: amount().clamp(0.0, 1.0));
      case 'saturate':
        final s = amount();
        return m([
          0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, //
          0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s,
          0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s,
        ]);
      case 'grayscale':
        final g = 1 - amount().clamp(0.0, 1.0);
        return m([
          0.2126 + 0.7874 * g, 0.7152 - 0.7152 * g, 0.0722 - 0.0722 * g, //
          0.2126 - 0.2126 * g, 0.7152 + 0.2848 * g, 0.0722 - 0.0722 * g,
          0.2126 - 0.2126 * g, 0.7152 - 0.7152 * g, 0.0722 + 0.9278 * g,
        ]);
      case 'sepia':
        final g = 1 - amount().clamp(0.0, 1.0);
        return m([
          0.393 + 0.607 * g, 0.769 - 0.769 * g, 0.189 - 0.189 * g, //
          0.349 - 0.349 * g, 0.686 + 0.314 * g, 0.168 - 0.168 * g,
          0.272 - 0.272 * g, 0.534 - 0.534 * g, 0.131 + 0.869 * g,
        ]);
      case 'hue-rotate':
        final t = arg.trim();
        final v = double.tryParse(t.replaceAll(RegExp(r'[a-z]+$'), '')) ?? 0;
        final rad = t.endsWith('turn')
            ? v * 2 * math.pi
            : t.endsWith('grad')
            ? v * math.pi / 200
            : t.endsWith('rad')
            ? v
            : v * math.pi / 180;
        final c = math.cos(rad), n = math.sin(rad);
        return m([
          0.213 + c * 0.787 - n * 0.213,
          0.715 - c * 0.715 - n * 0.715,
          0.072 - c * 0.072 + n * 0.928, //
          0.213 - c * 0.213 + n * 0.143,
          0.715 + c * 0.285 + n * 0.140,
          0.072 - c * 0.072 - n * 0.283,
          0.213 - c * 0.213 - n * 0.787,
          0.715 - c * 0.715 + n * 0.715,
          0.072 + c * 0.928 + n * 0.072,
        ]);
    }
    return null;
  }

  /// [w] through the CSS filter [f], its functions applied left to right as
  /// the page applies them: blur, drop-shadow and color changes.
  String _filter(String f, String w, _Ctx ctx) {
    for (final (name, arg) in _filterFunctions(f)) {
      switch (name) {
        case 'blur':
          final r = length(arg.isEmpty ? '0' : arg)?.value ?? 0;
          if (r > 0) {
            ctx.usesUi = true;
            w = 'ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: ${num(r)}, sigmaY: ${num(r)}), child: $w)';
          }
        case 'drop-shadow':
          final parts = splitTop(arg, ' ');
          final lens = [for (final p in parts) ?length(p)?.value];
          final color = [for (final p in parts) ?_color(p)].firstOrNull ?? 0xFF000000;
          if (lens.length >= 2) {
            final blur = lens.length > 2 ? lens[2] : 0.0;
            // Its blur radius is twice the deviation, as box-shadow's is.
            w = 'DropShadow(offset: Offset(${num(lens[0])}, ${num(lens[1])}), sigma: ${num(blur / 2)}, color: ${colorRef(color)}, child: $w)';
          }
        default:
          if (_colorMatrix(name, arg) case final m?) {
            w = 'ColorFiltered(colorFilter: ColorFilter.matrix(<double>[${m.map(num).join(', ')}]), child: $w)';
          }
      }
    }
    return w;
  }

  String _transform(String t, String w, double fs) {
    for (final m in RegExp(r'([a-zA-Z]+)\(([^)]*)\)').allMatches(t).toList().reversed) {
      final args = m[2]!.split(RegExp(r'\s*,\s*'));
      switch (m[1]!.toLowerCase()) {
        case 'translate' || 'translatex' || 'translatey':
          final x = m[1]!.toLowerCase() == 'translatey' ? null : length(args[0], fontSize: fs);
          final y = m[1]!.toLowerCase() == 'translatex'
              ? null
              : length(
                  m[1]!.toLowerCase() == 'translatey' ? args[0] : (args.length > 1 ? args[1] : '0'),
                  fontSize: fs,
                );
          w = 'Transform.translate(offset: Offset(${x?.code ?? '0'}, ${y?.code ?? '0'}), child: $w)';
        case 'scale':
          w = 'Transform.scale(scale: ${args[0]}, child: $w)';
        case 'rotate':
          final deg = double.tryParse(args[0].replaceAll('deg', '')) ?? 0;
          w = 'Transform.rotate(angle: ${num(deg * 3.141592653589793 / 180)}, child: $w)';
      }
    }
    return w;
  }

  /// Width, height and their limits as BoxConstraints; null when it has none.
  String? _constraints(DNode n, double fs, _Ctx ctx) {
    final s = n.style;
    final c = <String>[];
    void add(String key, String? v, String name) {
      final l = v == null ? null : length(v, fontSize: fs);
      if (l == null) return;
      c.add('$name: ${l.code}');
    }

    final w = s['width'], h = s['height'];
    if (w != null && length(w, fontSize: fs) != null) {
      add('width', w, 'minWidth');
      add('width', w, 'maxWidth');
    }
    if (h != null && length(h, fontSize: fs) != null) {
      add('height', h, 'minHeight');
      add('height', h, 'maxHeight');
    }
    add('min-width', s['min-width'], 'minWidth');
    add('max-width', s['max-width'], 'maxWidth');
    add('min-height', s['min-height'], 'minHeight');
    add('max-height', s['max-height'], 'maxHeight');
    if (c.isEmpty) return null;
    // One of each: the last said wins, as later declarations do in CSS.
    final byName = <String, String>{};
    for (final x in c) {
      final i = x.indexOf(':');
      byName[x.substring(0, i)] = x.substring(i + 1).trim();
    }
    if (byName.values.any((v) => v.contains('context'))) {
      ctx.usesMath = ctx.usesMath || byName.values.any((v) => v.contains('math.'));
    }
    return 'BoxConstraints(${byName.entries.map((e) => '${e.key}: ${e.value}').join(', ')})';
  }

  String? _insets(
    String? all,
    double fs,
    _Ctx ctx, {
    String? top,
    String? right,
    String? bottom,
    String? left,
  }) {
    final v = all == null ? ['0', '0', '0', '0'] : sides(all);
    final t = length(top ?? v[0], fontSize: fs), r = length(right ?? v[1], fontSize: fs);
    final b = length(bottom ?? v[2], fontSize: fs), l = length(left ?? v[3], fontSize: fs);
    final xs = [t, r, b, l];
    if (xs.every((x) => x == null || x.isZero)) return null;
    String code(DLen? x) => x?.code ?? '0';
    if (xs.every((x) => x?.code == t?.code)) return 'EdgeInsets.all(${code(t)})';
    return 'EdgeInsets.fromLTRB(${code(l)}, ${code(t)}, ${code(r)}, ${code(b)})';
  }

  // ---- Flex and grid ----------------------------------------------------------

  /// Flex items sized to their content, as a row lays out an item that
  /// does not grow: a row inside one shrink-wraps too.
  final _contentSized = <DNode>{};

  String _flex(DNode n, _Ctx ctx, _Text text) {
    final s = n.style;
    final dir = s['flex-direction'] ?? 'row';
    final row = dir.startsWith('row');
    final wrap = s['flex-wrap'] == 'wrap';
    final gaps = _gaps(s, text.size);
    final mainGap = row ? gaps.$2 : gaps.$1;
    final crossGap = row ? gaps.$1 : gaps.$2;
    final items = [
      for (final c in n.children)
        if (!(c.isText && c.text!.trim().isEmpty) && !(!c.isText && (_absolute(c) || _hidden(c))))
          c,
    ];
    final justify = _mainAlign(s['justify-content']);
    final align = s['align-items'];
    final inline = _display(n) == 'inline-flex';
    // Sized to its content, it has no space to share: nothing in it shrinks.
    final contentSized = inline || _contentSized.contains(n);
    if (wrap && row && items.any((c) => !c.isText && _basisOf(c) != null)) {
      // Lines broken by each item's basis, the room left shared by grow, as
      // CSS lays out a wrapping flex.
      final entries = <String>[];
      for (final c in items) {
        final w = _item(c, ctx, text, row: row, inFlex: false);
        if (w == null) continue;
        // A basis is its content's width: its padding and border go on top.
        var basis = c.isText ? null : _basisOf(c);
        final room = c.isText || c.style['box-sizing'] == 'border-box'
            ? 0.0
            : _sideRoom(c.style, text.size);
        if (basis != null && room > 0) {
          basis = basis.value != null
              ? DLen.px(basis.value! + room)
              : DLen('(${basis.code} + ${num(room)})', dynamic: true);
        }
        final grow = c.isText
            ? 0.0
            : (_growOf(c.style['flex']?.trim()) ??
                  double.tryParse(c.style['flex-grow'] ?? '') ??
                  0);
        entries.add(
          'FlexWrapItem(${basis == null ? '' : 'basis: ${basis.code}, '}grow: ${num(grow)}, order: ${_orderOf(c)}, child: ${_mediaWrap(c, w, ctx)})',
        );
      }
      final cross = switch (align) {
        'center' => 'CrossAxisAlignment.center',
        'flex-end' || 'end' => 'CrossAxisAlignment.end',
        _ => 'CrossAxisAlignment.start',
      };
      return 'FlexWrap(gap: ${mainGap?.code ?? '0'}, runGap: ${crossGap?.code ?? '0'}, crossAxisAlignment: $cross, '
          'items: [${entries.join(', ')}])';
    }
    if (wrap) {
      // A wrap's items are as wide as their content.
      _contentSized.addAll([
        for (final c in items)
          if (!c.isText) c,
      ]);
      final widgets = [for (final c in items) ?_item(c, ctx, text, row: row, inFlex: false)];
      final wrapped =
          'Wrap(direction: ${row ? 'Axis.horizontal' : 'Axis.vertical'}, spacing: ${mainGap?.code ?? '0'}, runSpacing: ${crossGap?.code ?? '0'}, '
          'alignment: ${_wrapAlign(s['justify-content'])}, crossAxisAlignment: ${_wrapCross(align)}, children: [${widgets.join(', ')}])';
      // Where it is not stretched, as wide as its content on one line, or
      // as its room if less (CSS's fit-content); a Wrap would take only its
      // widest line.
      // (A Wrap leaves its spacing out of how wide it says it would be.)
      final gaps = widgets.length < 2 || mainGap == null || mainGap.isZero
          ? ''
          : 'extra: ${mainGap.code} * ${widgets.length - 1}, ';
      return row ? 'FitContent(${gaps}child: $wrapped)' : wrapped;
    }
    final stretchRow =
        row &&
        (align == null || align == 'stretch' || align == 'normal') &&
        items.every(_intrinsicSafe);
    final cross = switch (align) {
      'center' => 'CrossAxisAlignment.center',
      'flex-end' || 'end' => 'CrossAxisAlignment.end',
      'baseline' => 'CrossAxisAlignment.baseline',
      'flex-start' || 'start' => 'CrossAxisAlignment.start',
      _ =>
        row
            ? (stretchRow ? 'CrossAxisAlignment.stretch' : 'CrossAxisAlignment.start')
            : 'CrossAxisAlignment.stretch',
    };
    final grows = items.any((c) {
      if (c.isText) return false;
      final g = c.style['flex-grow'] != null
          ? double.tryParse(c.style['flex-grow']!)
          : _growOf(c.style['flex']?.trim());
      return g != null && g > 0;
    });
    final children = <String>[];
    for (final c in items) {
      if (row && !c.isText) _contentSized.add(c);
      final w = _item(c, ctx, text, row: row, inFlex: true, lineGrows: grows || contentSized);
      if (w == null) continue;
      // An auto margin takes the free space: pushed along.
      final ms = c.isText ? null : (c.style['margin'] == null ? null : sides(c.style['margin']!));
      final before = row
          ? (c.isText ? null : c.style['margin-left'] ?? ms?[3])
          : (c.isText ? null : c.style['margin-top'] ?? ms?[0]);
      if (before == 'auto') children.add('Spacer()');
      children.add(_mediaItem(c, w));
    }
    var ordered = children;
    if (dir.endsWith('reverse')) ordered = children.reversed.toList();
    final flex =
        'Flex(direction: ${row ? 'Axis.horizontal' : 'Axis.vertical'}, mainAxisAlignment: $justify, crossAxisAlignment: $cross, '
        '${cross == 'CrossAxisAlignment.baseline' ? 'textBaseline: TextBaseline.alphabetic, ' : ''}'
        'mainAxisSize: ${inline || !row || _contentSized.contains(n) ? 'MainAxisSize.min' : 'MainAxisSize.max'}, '
        '${mainGap != null && !mainGap.isZero ? 'spacing: ${mainGap.code}, ' : ''}children: [${ordered.join(', ')}])';
    final direction = _mediaDirection(n);
    if (direction != null) {
      return 'Builder(builder: (context) => ${flex.replaceFirst("direction: ${row ? 'Axis.horizontal' : 'Axis.vertical'}", 'direction: $direction')})';
    }
    return stretchRow ? 'IntrinsicHeight(child: $flex)' : flex;
  }

  /// A flex item's basis in px, from flex or flex-basis; null for auto.
  DLen? _basisOf(DNode c) {
    final b =
        c.style['flex-basis'] ??
        (() {
          final p = (c.style['flex'] ?? '').trim().split(RegExp(r'\s+'));
          return p.length == 3 ? p[2] : null;
        })();
    return b == null ? null : length(b);
  }

  /// Its order, as code: a width rule may change it.
  String _orderOf(DNode c) {
    final own = int.tryParse(c.style['order']?.replaceAll('!important', '').trim() ?? '') ?? 0;
    for (final cls in c.classes) {
      for (final (width, max, prop, value)
          in _media[cls] ?? const <(double, bool, String, String)>[]) {
        if (prop == 'order') {
          return 'MediaQuery.sizeOf(context).width ${max ? '<=' : '>'} ${num(width)} ? ${int.tryParse(value) ?? 0} : $own';
        }
      }
    }
    return '$own';
  }

  bool _intrinsicSafe(DNode n) {
    if (n.isText) return true;
    if ((n.style['flex-wrap'] ?? '') == 'wrap') return false;
    if (n.tag == 'img' || n.tag == 'svg') return true;
    return n.children.every(_intrinsicSafe);
  }

  /// A flex item: itself, growing or shrinking as its flex says.
  String? _item(
    DNode c,
    _Ctx ctx,
    _Text text, {
    required bool row,
    required bool inFlex,
    bool lineGrows = false,
  }) {
    final w = c.isText ? _inline([c], ctx, text, c.parent!) : _element(c, ctx, text);
    if (w == null || c.isText) return w;
    if (!inFlex) {
      // A grid's or a wrap's item: its margins kept, never collapsed.
      return _keepMargins(_verticalMargins(c, _textOf(c, text)), w);
    }
    final s = c.style;
    final flex = s['flex']?.trim();
    final grow = s['flex-grow'] != null ? double.tryParse(s['flex-grow']!) : _growOf(flex);
    final shrink = s['flex-shrink'] != null ? double.tryParse(s['flex-shrink']!) : _shrinkOf(flex);
    // Top and bottom margins in a flex line stay with the item.
    final item = _keepMargins(_verticalMargins(c, _textOf(c, text)), w);
    if (grow != null && grow > 0) {
      return 'Expanded(flex: ${grow.round().clamp(1, 1000)}, child: $item)';
    }
    // Text shrinks to fit, as flex-shrink 1 lets it, in a line where nothing
    // grows: where something does, the text keeps its width and the growing
    // item takes what is left, as CSS lays it out.
    if (row &&
        !lineGrows &&
        (shrink ?? 1) > 0 &&
        c.descendants.any((d) => d.isText && d.text!.trim().isNotEmpty) &&
        !_fixedWidth(c)) {
      // Shrinks where it must, and is otherwise as wide as its content.
      return _isText(item)
          ? 'Flexible(child: $item)'
          : 'Flexible(child: IntrinsicWidth(child: $item))';
    }
    // In a row, an item that does not grow is as wide as its content, as
    // CSS gives it; Flutter would give it all the width there is.
    if (row && !_fixedWidth(c) && c.tag != 'img' && c.tag != 'svg' && !_isText(item)) {
      return 'IntrinsicWidth(child: $item)';
    }
    return item;
  }

  bool _isText(String w) =>
      w.startsWith('Text.rich(') || w.startsWith('Text(') || w.startsWith('CssText(');

  bool _fixedWidth(DNode c) => c.style['width'] != null && length(c.style['width']!) != null;

  double? _growOf(String? flex) {
    if (flex == null || flex == 'none' || flex == 'auto' || flex == 'initial') {
      return flex == 'auto' ? 1 : null;
    }
    return double.tryParse(flex.split(RegExp(r'\s+')).first);
  }

  double? _shrinkOf(String? flex) {
    if (flex == null) return null;
    if (flex == 'none') return 0;
    final p = flex.split(RegExp(r'\s+'));
    return p.length > 1 ? double.tryParse(p[1]) : 1;
  }

  /// Row and column gaps.
  (DLen?, DLen?) _gaps(Map<String, String> s, double fs) {
    DLen? row, col;
    if (s['gap'] case final g?) {
      final p = splitTop(g, ' ');
      row = length(p[0], fontSize: fs);
      col = length(p.length > 1 ? p[1] : p[0], fontSize: fs);
    }
    if (s['row-gap'] case final g?) row = length(g, fontSize: fs);
    if (s['column-gap'] case final g?) col = length(g, fontSize: fs);
    return (row, col);
  }

  String _mainAlign(String? v) => switch (v) {
    'center' => 'MainAxisAlignment.center',
    'flex-end' || 'end' => 'MainAxisAlignment.end',
    'space-between' => 'MainAxisAlignment.spaceBetween',
    'space-around' => 'MainAxisAlignment.spaceAround',
    'space-evenly' => 'MainAxisAlignment.spaceEvenly',
    _ => 'MainAxisAlignment.start',
  };

  String _wrapAlign(String? v) => switch (v) {
    'center' => 'WrapAlignment.center',
    'flex-end' || 'end' => 'WrapAlignment.end',
    'space-between' => 'WrapAlignment.spaceBetween',
    'space-around' => 'WrapAlignment.spaceAround',
    'space-evenly' => 'WrapAlignment.spaceEvenly',
    _ => 'WrapAlignment.start',
  };

  String _wrapCross(String? v) => switch (v) {
    'center' => 'WrapCrossAlignment.center',
    'flex-end' || 'end' => 'WrapCrossAlignment.end',
    _ => 'WrapCrossAlignment.start',
  };

  String _grid(DNode n, _Ctx ctx, _Text text) {
    final s = n.style;
    final gaps = _gaps(s, text.size);
    final items = [
      for (final c in n.children)
        if (!(c.isText && c.text!.trim().isEmpty) && !(!c.isText && (_absolute(c) || _hidden(c))))
          c,
    ];
    final place = s['place-items'] ?? s['align-items'];
    final center = place == 'center';
    final template = s['grid-template-columns'];
    if (template == null) {
      // One column: each item a row of its own.
      final widgets = [for (final c in items) ?_item(c, ctx, text, row: false, inFlex: false)];
      if (widgets.length == 1 && center) return 'Center(child: ${widgets.single})';
      final column =
          'Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: ${center ? 'CrossAxisAlignment.center' : 'CrossAxisAlignment.stretch'}, '
          '${gaps.$1 != null && !gaps.$1!.isZero ? 'spacing: ${gaps.$1!.code}, ' : ''}children: [${widgets.join(', ')}])';
      // Its column is at least as wide as what will not wrap in it.
      return 'GridTrack(child: $column)';
    }
    // As many equal columns as fit at a least width: worked out from the
    // width there is, as the page does.
    final fit = RegExp(r'^repeat\(\s*(auto-fill|auto-fit)\s*,\s*minmax\((.+),\s*1fr\s*\)\s*\)$')
        .firstMatch(template.trim());
    if (fit != null) {
      final least = fit[2]!.trim();
      final pct = RegExp(r'^min\(\s*100%\s*,\s*(.+)\)$').firstMatch(least);
      final px = length(pct?[1] ?? least, fontSize: text.size);
      if (px != null) {
        final widgets = [
          for (final c in items)
            _item(c, ctx, text, row: false, inFlex: false) ?? 'SizedBox.shrink()',
        ];
        return 'DesignGrid(least: ${px.code}, fill: ${fit[1] == 'auto-fill'}, '
            'columnGap: ${gaps.$2?.code ?? '0'}, rowGap: ${gaps.$1?.code ?? '0'}, '
            'stretch: ${!center}, children: [${widgets.join(', ')}])';
      }
    }
    final tracks = template
        .replaceAllMapped(
          RegExp(r'repeat\(\s*(\d+)\s*,\s*([^)]+)\)'),
          (m) => List.filled(int.parse(m[1]!), m[2]!.trim()).join(' '),
        )
        .trim()
        .split(RegExp(r'\s+'));
    final rows = <String>[];
    for (var i = 0; i < items.length; i += tracks.length) {
      final cells = <String>[];
      for (var j = 0; j < tracks.length; j++) {
        final c = i + j < items.length ? items[i + j] : null;
        final w = c == null
            ? 'SizedBox.shrink()'
            : (_item(c, ctx, text, row: false, inFlex: false) ?? 'SizedBox.shrink()');
        final track = tracks[j];
        if (track.endsWith('fr')) {
          cells.add(
            'Expanded(flex: ${((double.tryParse(track.replaceAll('fr', '')) ?? 1) * 100).round()}, child: $w)',
          );
        } else {
          cells.add('SizedBox(width: ${length(track)?.code ?? '0'}, child: $w)');
        }
      }
      final cross = center ? 'CrossAxisAlignment.center' : 'CrossAxisAlignment.stretch';
      final row =
          'Row(crossAxisAlignment: $cross, ${gaps.$2 != null && !gaps.$2!.isZero ? 'spacing: ${gaps.$2!.code}, ' : ''}children: [${cells.join(', ')}])';
      rows.add(center ? row : 'IntrinsicHeight(child: $row)');
    }
    return 'Column(crossAxisAlignment: CrossAxisAlignment.stretch, ${gaps.$1 != null && !gaps.$1!.isZero ? 'spacing: ${gaps.$1!.code}, ' : ''}children: [${rows.join(', ')}])';
  }

  // ---- Width rules, links, components -----------------------------------------

  /// `@media (max-width: 720px) { .hide-sm { display: none } }`, read.
  Map<String, List<(double, bool, String, String)>> _mediaRules(String css) {
    final out = <String, List<(double, bool, String, String)>>{};
    final media = RegExp(
      r'@media\s*\(\s*(max|min)-width\s*:\s*([\d.]+)px\s*\)\s*\{((?:[^{}]*\{[^{}]*\})*)\s*\}',
    );
    for (final m in media.allMatches(css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ''))) {
      final max = m[1] == 'max';
      final width = double.parse(m[2]!);
      for (final r in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(m[3]!)) {
        for (final cls in r[1]!.split(',')) {
          final name = cls.trim().replaceFirst('.', '');
          for (final e in parseStyle(r[2]!).entries) {
            (out[name] ??= []).add((
              width,
              max,
              e.key,
              e.value.replaceAll('!important', '').trim(),
            ));
          }
        }
      }
    }
    return out;
  }

  /// [w], hidden where a width rule of its classes hides it.
  String _mediaWrap(DNode n, String w, _Ctx ctx) {
    if (n.isText) return w;
    for (final cls in n.classes) {
      for (final (width, max, prop, value)
          in _media[cls] ?? const <(double, bool, String, String)>[]) {
        if (prop == 'display' && value == 'none') {
          return 'ShowWhen(${max ? 'above: ${num(width)}' : 'atMost: ${num(width)}'}, child: $w)';
        }
      }
    }
    return w;
  }

  /// When [n] is shown, as code, where a width rule hides it; null otherwise.
  String? _shownIf(DNode n) {
    if (n.isText) return null;
    for (final cls in n.classes) {
      for (final (width, max, prop, value)
          in _media[cls] ?? const <(double, bool, String, String)>[]) {
        if (prop == 'display' && value == 'none') {
          return 'MediaQuery.sizeOf(context).width ${max ? '>' : '<='} ${num(width)}';
        }
      }
    }
    return null;
  }

  /// [w] as an item of a list of children, left out where a width rule hides
  /// it, as display: none takes it out of the line, gaps and all.
  String _mediaItem(DNode n, String w) => switch (_shownIf(n)) {
    final c? => 'if ($c) $w',
    null => w,
  };

  /// A flex direction a width rule changes: the expression choosing it.
  String? _mediaDirection(DNode n) {
    for (final cls in n.classes) {
      for (final (width, max, prop, value)
          in _media[cls] ?? const <(double, bool, String, String)>[]) {
        if (prop == 'flex-direction') {
          final other = value.startsWith('row') ? 'Axis.horizontal' : 'Axis.vertical';
          final own = (n.style['flex-direction'] ?? 'row').startsWith('row')
              ? 'Axis.horizontal'
              : 'Axis.vertical';
          return 'MediaQuery.sizeOf(context).width ${max ? '<=' : '>'} ${num(width)} ? $other : $own';
        }
      }
    }
    return null;
  }

  String _link(String? href, String w, _Ctx ctx, DNode n) {
    final target = href == null ? 'null' : _routeOrUrl(href);
    if (flavor == FlutterFlavor.ashlar) {
      ctx.imports.add('ui/core/ashlar/pressable.dart');
      return 'Pressable(onPressed: () => openLink(context, $target), builder: (context, state) => $w)';
    }
    return 'MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: () => openLink(context, $target), child: $w))';
  }

  /// A link as code: another screen's route, or the address as it is.
  String _routeOrUrl(String href) {
    if (!href.startsWith('"')) return href; // a parameter: its value decides
    final raw = jsonDecode(href) as String;
    final file = raw.split('#').first.replaceFirst(RegExp(r'^\./'), '');
    if (routes[file] case final r?) return jsonEncode(r);
    return href;
  }

  /// Where [n] is in the page, as code: inside a component, from where
  /// that use of it is ([at]).
  String _measureAt(DNode n, _Ctx ctx) {
    final c = ctx.component;
    if (c == null) return jsonEncode(n.selector);
    return "'\$at${n.selector.substring(c.model.selector.length).replaceAll(r'$', r'\$')}'";
  }

  String _measureKey(DNode n, _Ctx ctx) => ctx.component == null
      ? 'const ValueKey(${jsonEncode(n.selector)})'
      : 'ValueKey(${_measureAt(n, ctx)})';

  String _use(DComponent c, DNode use, _Ctx ctx) {
    ctx.imports.add('ui/core/widgets/${snake(c.name)}.dart');
    final args = c.argsOf(use);
    final props = <String>[];
    for (final p in c.params) {
      var at = use;
      for (final i in p.path) {
        at = at.children[i];
      }
      final own = ctx.paramAt(at, p.kind, p.attr);
      if (own != null) {
        props.add('${p.name}: ${own.name}');
        continue;
      }
      final v = args[p.name]!;
      switch (p.kind) {
        case DParamKind.text:
          props.add('${p.name}: ${jsonEncode(v)}');
        case DParamKind.attr:
          final s = v as String;
          if (p.attr == 'href') {
            final file = s.split('#').first;
            props.add('${p.name}: ${jsonEncode(routes[file] ?? s)}');
          } else if (p.attr == 'src' && !s.contains(':')) {
            assets.add(s);
            props.add('${p.name}: ${jsonEncode('assets/$s')}');
          } else {
            props.add('${p.name}: ${jsonEncode(s)}');
          }
        case DParamKind.element:
          final w = _element(v as DNode, ctx.inUse(), _inherited(v)) ?? 'SizedBox.shrink()';
          props.add('${p.name}: $w');
      }
    }
    if (measure) props.add('at: ${_measureAt(use, ctx)}');
    return '${c.name}(${props.join(', ')})';
  }

  // ---- The app around it ------------------------------------------------------

  String _designFile() {
    final colors = [
      for (final t in plan.tokens)
        if (t.kind == DTokenKind.color && colorValue(t.value) != null) t,
    ];
    final families = [
      for (final t in plan.tokens)
        if (t.kind == DTokenKind.font) t,
    ];
    return [
      "import 'dart:ui' show ImageFilter;",
      '',
      "import 'package:flutter/rendering.dart';",
      "import 'package:flutter/widgets.dart';",
      "import 'package:flutter_svg/flutter_svg.dart';",
      if (flavor == FlutterFlavor.plain) "import 'package:url_launcher/url_launcher.dart';",
      if (flavor == FlutterFlavor.ashlar) "import 'package:url_launcher/url_launcher.dart';",
      '',
      "/// The design's colors, named as its theme names them.",
      'abstract final class DesignColors {',
      for (final t in colors) '  static const ${t.name} = ${colorCode(colorValue(t.value)!)};',
      '}',
      '',
      "/// The design's typefaces, bundled under these names (pubspec.yaml).",
      'abstract final class DesignFonts {',
      for (final t in families)
        "  static const ${t.name} = ${jsonEncode(_family(t.value) ?? 'sans-serif')};",
      '}',
      '',
      "/// [v]% of the screen's width, as CSS's vw.",
      'double vw(BuildContext context, double v) => MediaQuery.sizeOf(context).width * v / 100;',
      '',
      "/// [v]% of the screen's height, as CSS's vh.",
      'double vh(BuildContext context, double v) => MediaQuery.sizeOf(context).height * v / 100;',
      '',
      '/// Shown only above or at most a width, as the design\'s width rules say.',
      'class ShowWhen extends StatelessWidget {',
      '  const ShowWhen({super.key, this.above, this.atMost, required this.child});',
      '  final double? above;',
      '  final double? atMost;',
      '  final Widget child;',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    final w = MediaQuery.sizeOf(context).width;',
      '    final shown = (above == null || w > above!) && (atMost == null || w <= atMost!);',
      '    return shown ? child : const SizedBox.shrink();',
      '  }',
      '}',
      '',
      '/// One item of a [FlexWrap]: its basis (null: as wide as the line), how',
      '/// much of the room left it takes, and where it goes in order.',
      'class FlexWrapItem {',
      '  const FlexWrapItem({this.basis, this.grow = 0, this.order = 0, required this.child});',
      '  final double? basis;',
      '  final double grow;',
      '  final int order;',
      '  final Widget child;',
      '}',
      '',
      '/// A wrapping flex row as CSS lays it out: lines broken where the next',
      '/// basis does not fit, each line\'s room left shared out by grow.',
      'class FlexWrap extends StatelessWidget {',
      '  const FlexWrap({super.key, this.gap = 0, this.runGap = 0, this.crossAxisAlignment = CrossAxisAlignment.start, required this.items});',
      '  final double gap, runGap;',
      '  final CrossAxisAlignment crossAxisAlignment;',
      '  final List<FlexWrapItem> items;',
      '',
      '  @override',
      '  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {',
      '    final w = box.maxWidth;',
      '    final order = List.generate(items.length, (i) => i)..sort((a, b) => items[a].order != items[b].order ? items[a].order.compareTo(items[b].order) : a.compareTo(b));',
      '    final lines = <List<FlexWrapItem>>[[]];',
      '    var used = 0.0;',
      '    for (final it in [for (final i in order) items[i]]) {',
      '      final b = it.basis ?? w;',
      '      final need = lines.last.isEmpty ? b : used + gap + b;',
      '      if (lines.last.isNotEmpty && need > w) { lines.add([]); used = 0; }',
      '      used = lines.last.isEmpty ? b : used + gap + b;',
      '      lines.last.add(it);',
      '    }',
      '    final rows = <Widget>[];',
      '    for (final line in lines) {',
      '      final bases = [for (final it in line) (it.basis ?? w).clamp(0.0, w)];',
      '      final free = w - bases.fold(0.0, (a, b) => a + b) - gap * (line.length - 1);',
      '      final grow = line.fold(0.0, (a, it) => a + it.grow);',
      '      rows.add(Row(crossAxisAlignment: crossAxisAlignment, spacing: gap, children: [',
      '        for (final (i, it) in line.indexed)',
      '          SizedBox(width: (bases[i] + (free > 0 && grow > 0 ? free * it.grow / (grow < 1 ? 1 : grow) : (free < 0 ? free * bases[i] / bases.fold(0.0, (a, b) => a + b) : 0))).clamp(0.0, w), child: it.child),',
      '      ]));',
      '    }',
      '    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: runGap, children: rows);',
      '  });',
      '}',
      '',
      '/// A grid of as many equal columns as fit at [least] wide, as CSS\'s',
      '/// repeat(auto-fill/auto-fit, minmax(least, 1fr)) lays it out.',
      'class DesignGrid extends StatelessWidget {',
      '  const DesignGrid({super.key, required this.least, this.fill = true, this.columnGap = 0, this.rowGap = 0, this.stretch = true, required this.children});',
      '  final double least;',
      '  /// auto-fill keeps empty columns; auto-fit lets the items have their room.',
      '  final bool fill;',
      '  final double columnGap, rowGap;',
      '  final bool stretch;',
      '  final List<Widget> children;',
      '',
      '  @override',
      '  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {',
      '    final w = box.maxWidth;',
      '    final min = least < w ? least : w;',
      '    var n = ((w + columnGap) / (min + columnGap)).floor().clamp(1, 1000);',
      '    if (!fill && children.isNotEmpty && n > children.length) n = children.length;',
      '    final rows = <Widget>[];',
      '    for (var i = 0; i < children.length; i += n) {',
      '      final row = Row(',
      '        crossAxisAlignment: stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,',
      '        spacing: columnGap,',
      '        children: [for (var j = i; j < i + n; j++) Expanded(child: j < children.length ? children[j] : const SizedBox.shrink())],',
      '      );',
      '      rows.add(stretch ? IntrinsicHeight(child: row) : row);',
      '    }',
      '    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: rowGap, children: rows);',
      '  });',
      '}',
      '',
      '/// Margins CSS has and padding cannot be: negative ones, pulling it over',
      '/// what is before it, its own height less the pull.',
      'class Margin extends SingleChildRenderObjectWidget {',
      '  const Margin({super.key, this.top = 0, this.bottom = 0, super.child});',
      '  final double top;',
      '  final double bottom;',
      '',
      '  @override',
      '  RenderObject createRenderObject(BuildContext context) => RenderMargin(top, bottom);',
      '',
      '  @override',
      '  void updateRenderObject(BuildContext context, RenderMargin renderObject) =>',
      '      renderObject..top = top..bottom = bottom;',
      '}',
      '',
      'class RenderMargin extends RenderShiftedBox {',
      '  RenderMargin(this._top, this._bottom) : super(null);',
      '  double _top, _bottom;',
      '  set top(double v) { _top = v; markNeedsLayout(); }',
      '  set bottom(double v) { _bottom = v; markNeedsLayout(); }',
      '',
      '  @override',
      '  void performLayout() {',
      '    final c = child;',
      '    if (c == null) { size = constraints.smallest; return; }',
      '    c.layout(constraints.loosen().copyWith(maxHeight: double.infinity), parentUsesSize: true);',
      '    (c.parentData! as BoxParentData).offset = Offset(0, _top);',
      '    size = constraints.constrain(Size(c.size.width, (c.size.height + _top + _bottom).clamp(0, double.infinity)));',
      '  }',
      '}',
      '',
      '/// As wide as its content on one line, or as its room if less (CSS fit-content).',
      '/// [extra] is room its content leaves out of how wide it says it is.',
      'class FitContent extends SingleChildRenderObjectWidget {',
      '  const FitContent({super.key, this.extra = 0, super.child});',
      '  final double extra;',
      '',
      '  @override',
      '  RenderObject createRenderObject(BuildContext context) => RenderFitContent(extra);',
      '',
      '  @override',
      '  void updateRenderObject(BuildContext context, RenderFitContent renderObject) =>',
      '      renderObject.extra = extra;',
      '}',
      '',
      'class RenderFitContent extends RenderProxyBox {',
      '  RenderFitContent(this._extra);',
      '  double _extra;',
      '  set extra(double v) {',
      '    _extra = v;',
      '    markNeedsLayout();',
      '  }',
      '',
      '  @override',
      '  double computeMaxIntrinsicWidth(double height) => (child?.getMaxIntrinsicWidth(height) ?? 0) + _extra;',
      '',
      '  @override',
      '  void performLayout() {',
      '    final c = child;',
      '    if (c == null) { size = constraints.smallest; return; }',
      '    final w = constraints.constrainWidth(c.getMaxIntrinsicWidth(double.infinity) + _extra);',
      '    c.layout(constraints.tighten(width: w), parentUsesSize: true);',
      '    size = constraints.constrain(c.size);',
      '  }',
      '}',
      '',
      '/// A width that is a share of the width of the line, as CSS percentages are:',
      '/// each is worked out from the room it is given (b), then held to its limits.',
      '/// Where the room has no end (an item of a row), it is as wide as its content.',
      'class PercentWidth extends SingleChildRenderObjectWidget {',
      '  const PercentWidth({super.key, this.width, this.minWidth, this.maxWidth, super.child});',
      '  final double Function(double b)? width, minWidth, maxWidth;',
      '',
      '  @override',
      '  RenderObject createRenderObject(BuildContext context) => RenderPercentWidth(width, minWidth, maxWidth);',
      '',
      '  @override',
      '  void updateRenderObject(BuildContext context, RenderPercentWidth renderObject) => renderObject',
      '    ..width = width',
      '    ..minWidth = minWidth',
      '    ..maxWidth = maxWidth',
      '    ..markNeedsLayout();',
      '}',
      '',
      'class RenderPercentWidth extends RenderShiftedBox {',
      '  RenderPercentWidth(this.width, this.minWidth, this.maxWidth) : super(null);',
      '  double Function(double b)? width, minWidth, maxWidth;',
      '',
      '  @override',
      '  void performLayout() {',
      '    final c = child;',
      '    if (c == null) { size = constraints.smallest; return; }',
      '    var inner = constraints;',
      '    if (constraints.hasBoundedWidth) {',
      '      final b = constraints.maxWidth;',
      '      final lo = (minWidth?.call(b) ?? 0).clamp(0.0, b);',
      '      final hi = (maxWidth?.call(b) ?? b).clamp(lo, b);',
      '      final w = width?.call(b);',
      '      inner = BoxConstraints(',
      '        minWidth: w == null ? lo : w.clamp(lo, hi),',
      '        maxWidth: w == null ? hi : w.clamp(lo, hi),',
      '        minHeight: constraints.minHeight,',
      '        maxHeight: constraints.maxHeight,',
      '      );',
      '    }',
      '    c.layout(inner, parentUsesSize: true);',
      '    (c.parentData! as BoxParentData).offset = Offset.zero;',
      '    size = constraints.constrain(c.size);',
      '  }',
      '}',
      '',
      '/// Each picture\'s own size, as its file has it: what the page lays an',
      '/// <img> out by before it has loaded.',
      'const designImageSizes = <String, (double, double)>{',
      for (final a in assets.toList()..sort())
        if (imageSize?.call(a) case final z?)
          '  ${jsonEncode('assets/$a')}: (${num(z.$1)}, ${num(z.$2)}),',
      '};',
      '',
      '/// A picture from the app\'s assets or the web. Given one of its sizes, the',
      '/// other keeps its proportions; given none, it is as large as its file says',
      '/// when [natural], or as wide as it is let be, in proportion, otherwise.',
      'Widget designImage(String src, {BoxFit fit = BoxFit.cover, double? width, double? height, bool natural = false}) {',
      '  if (designImageSizes[src] case (final ow, final oh) when ow > 0 && oh > 0) {',
      '    if (width != null && height == null) {',
      '      height = width * oh / ow;',
      '    } else if (height != null && width == null) {',
      '      width = height * ow / oh;',
      '    } else if (width == null && height == null) {',
      '      if (natural) {',
      '        (width, height) = (ow, oh);',
      '      } else {',
      '        return AspectRatio(aspectRatio: ow / oh, child: designImage(src, fit: fit, width: double.infinity, height: double.infinity));',
      '      }',
      '    }',
      '  }',
      "  final web = src.startsWith('http');",
      "  if (src.endsWith('.svg')) {",
      '    // In the box it is given, as an <img> keeps its size whatever the drawing.',
      '    final svg = web',
      '        ? SvgPicture.network(src, fit: BoxFit.contain, width: width, height: height)',
      '        : SvgPicture.asset(src, fit: BoxFit.contain, width: width, height: height);',
      '    return width != null && height != null ? SizedBox(width: width, height: height, child: svg) : svg;',
      '  }',
      '  return web',
      '      ? Image.network(src, fit: fit, width: width, height: height)',
      '      : Image.asset(src, fit: fit, width: width, height: height);',
      '}',
      '',
      '/// Goes where a link points: another screen, or the web.',
      'void openLink(BuildContext context, String? to) {',
      '  if (to == null || to.isEmpty) return;',
      "  if (to.startsWith('/')) {",
      "    Navigator.of(context).pushNamed(to.split('#').first);",
      '    return;',
      '  }',
      '  launchUrl(Uri.parse(to));',
      '}',
      '',
      cssTextSource,
      gridTrackSource,
      dropShadowSource,
    ].join('\n');
  }

  String _main() {
    final imports = [
      "import 'package:flutter/widgets.dart';",
      if (flavor == FlutterFlavor.ashlar) "import 'package:$package/ui/core/ashlar/app.dart';",
      if (flavor == FlutterFlavor.ashlar) "import 'package:$package/ui/core/ashlar/theme.dart';",
      if (flavor == FlutterFlavor.ashlar) "import 'package:$package/ui/core/design.dart';",
      for (final s in plan.screens)
        "import 'package:$package/ui/${snake(screenNames[s]!)}/widgets/${snake(screenNames[s]!)}_screen.dart';",
    ];
    final routeMap = [
      for (final s in plan.screens)
        "    '${routes[s.file]}': (context) => const ${screenNames[s]}Screen(),",
    ];
    final title = jsonEncode(plan.title);
    if (flavor == FlutterFlavor.ashlar) {
      final bg = plan.tokens.where((t) => t.name == 'surface').firstOrNull;
      final fg = plan.tokens.where((t) => t.name == 'text').firstOrNull;
      return [
        ...imports,
        '',
        'void main() => runApp(const App());',
        '',
        '/// Ashlar\'s dark theme, its page and text the design\'s own.',
        '///',
        '/// tapTarget 0: a link or button is the size the design draws it. Ashlar',
        '/// would grow each to 44 (iOS) or 48 (Android) for a finger, which moves',
        '/// everything around it; set it to null to have that instead.',
        'AshlarThemeData designTheme() => AshlarThemeData(',
        '  brightness: Brightness.dark,',
        '  colors: AshlarColors.dark.copyWith(${[if (bg != null) 'background: DesignColors.${bg.name}', if (fg != null) 'foreground: DesignColors.${fg.name}'].join(', ')}),',
        '  tapTarget: 0,',
        ');',
        '',
        'class App extends StatelessWidget {',
        '  const App({super.key});',
        '',
        '  @override',
        '  Widget build(BuildContext context) {',
        '    return AshlarApp(',
        '      title: $title,',
        '      themeMode: AshlarThemeMode.dark,',
        '      darkTheme: designTheme(),',
        '      routes: {',
        ...routeMap,
        '      },',
        '    );',
        '  }',
        '}',
        '',
      ].join('\n');
    }
    return [
      ...imports,
      '',
      'void main() => runApp(const App());',
      '',
      'class App extends StatelessWidget {',
      '  const App({super.key});',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    return WidgetsApp(',
      '      title: $title,',
      '      color: const Color(0xFF000000),',
      "      initialRoute: '/',",
      '      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),',
      '      routes: {',
      ...routeMap,
      '      },',
      '    );',
      '  }',
      '}',
      '',
    ].join('\n');
  }

  String _pubspec() => [
    'name: $package',
    'description: ${jsonEncode('${plan.title}, from its design.')}',
    "publish_to: 'none'",
    'version: 1.0.0+1',
    '',
    'environment:',
    '  sdk: ^3.8.0',
    '',
    'dependencies:',
    '  flutter:',
    '    sdk: flutter',
    '  flutter_svg: ^2.0.0',
    '  url_launcher: ^6.3.0',
    '',
    'dev_dependencies:',
    '  flutter_test:',
    '    sdk: flutter',
    '  flutter_lints: ^5.0.0',
    '',
    'flutter:',
    if (fontFiles.isNotEmpty) ...[
      '  fonts:',
      for (final family in {for (final f in fontFiles) f.family}) ...[
        '    - family: $family',
        '      fonts:',
        for (final f in fontFiles.where((f) => f.family == family)) ...[
          '        - asset: ${f.asset}',
          '          weight: ${f.weight}',
          if (f.italic) '          style: italic',
        ],
      ],
    ],
    if (assets.isNotEmpty) ...[
      '  assets:',
      for (final dir in {
        for (final a in assets)
          'assets/${a.contains('/') ? '${a.substring(0, a.lastIndexOf('/'))}/' : ''}',
      })
        '    - $dir',
    ],
    '',
  ].join('\n');

  String _measureTest() => [
    "import 'dart:convert';",
    "import 'dart:io';",
    '',
    "import 'package:flutter/services.dart';",
    "import 'package:flutter/widgets.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
    if (flavor == FlutterFlavor.ashlar) "import 'package:$package/main.dart';",
    if (flavor == FlutterFlavor.ashlar) "import 'package:$package/ui/core/ashlar/theme.dart';",
    for (final s in plan.screens)
      "import 'package:$package/ui/${snake(screenNames[s]!)}/widgets/${snake(screenNames[s]!)}_screen.dart';",
    '',
    '/// Where every element lands, at each width: for comparing with the page.',
    'void main() {',
    '  setUpAll(() async {',
    "    for (final f in Directory('assets/fonts').existsSync() ? Directory('assets/fonts').listSync() : <FileSystemEntity>[]) {",
    '      if (f is! File) continue;',
    "      final family = f.uri.pathSegments.last.split('-').first.replaceAll('_', ' ');",
    '      final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));',
    '      await loader.load();',
    '    }',
    '  });',
    for (final s in plan.screens)
      for (final width in [390, 834, 1440])
        "  testWidgets('${s.file} @$width', (tester) async { await measure(tester, const ${screenNames[s]}Screen(), '${s.file}', $width); });",
    '}',
    '',
    'Future<void> measure(WidgetTester tester, Widget screen, String file, double width) async {',
    '  tester.view.devicePixelRatio = 1;',
    '  tester.view.physicalSize = Size(width, 20000);',
    '  addTearDown(tester.view.reset);',
    '  await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: MediaQuery(data: MediaQueryData(size: Size(width, 900)), child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: ${flavor == FlutterFlavor.ashlar ? 'AshlarTheme(data: designTheme(), child: screen)' : 'screen'})))));',
    '  await tester.pump();',
    '  final out = <String, List<double>>{};',
    '  for (final e in find.byWidgetPredicate((w) => w is KeyedSubtree && w.key is ValueKey<String>).evaluate()) {',
    '    final key = ((e.widget as KeyedSubtree).key as ValueKey<String>).value;',
    '    final box = e.renderObject is RenderBox ? e.renderObject as RenderBox : e.findRenderObject() as RenderBox?;',
    '    if (box == null || !box.hasSize) continue;',
    '    final o = box.localToGlobal(Offset.zero);',
    '    out[key] = [o.dx, o.dy, box.size.width, box.size.height];',
    '  }',
    "  final dir = Directory('build/measure')..createSync(recursive: true);",
    "  File('\${dir.path}/\$file-\$width.json').writeAsStringSync(jsonEncode(out));",
    '}',
    '',
  ].join('\n');
}

class _Ctx {
  _Ctx(this.w, {required this.from, required this.screen, required this.partsOf, this.component});
  final _FlutterWriter w;
  final String from;
  final DScreen screen;
  final Map<DNode, DPart> partsOf;
  final DComponent? component;
  final imports = <String>{};
  final pieces = <String>[];
  bool usesMath = false, usesUi = false, usesGestures = false, usesSvg = false;
  bool noParams = false;

  _Ctx inUse() => this;

  DParam? paramAt(DNode n, DParamKind kind, [String? attr]) {
    final c = component;
    if (c == null || noParams) return null;
    final path = <int>[];
    var at = n;
    while (!identical(at, c.model)) {
      final p = at.parent;
      if (p == null) return null;
      path.insert(0, p.children.indexOf(at));
      at = p;
    }
    for (final p in c.params) {
      if (p.kind == kind && p.attr == attr && p.path.length == path.length) {
        var same = true;
        for (var i = 0; i < path.length; i++) {
          if (p.path[i] != path[i]) same = false;
        }
        if (same) return p;
      }
    }
    return null;
  }
}

/// "DownloadLink" -> "download_link".
String snake(String pascalName) =>
    pascalName.replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => '_${m[1]}').toLowerCase();

/// The design's own CSS, for reading width rules from a style block.
Map<String, String> styleOf(String text) => parseStyle(text);
