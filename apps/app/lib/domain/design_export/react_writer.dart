import 'dart:convert';

import 'design_model.dart';
import 'planner.dart';

/// A design as a React project (Vite, TypeScript, React Router), 1:1: React
/// draws the same elements with the same styles, so only the syntax moves.
/// Every screen a file that places its parts, every part a file, every
/// component a file, the theme one stylesheet. Paths to the files' text;
/// [assets] are the design's own files the pages use, to copy into `public/`.
({Map<String, String> files, Set<String> assets}) writeReact(DesignPlan plan) {
  final w = _ReactWriter(plan);
  return (files: w.files(), assets: w.assets);
}

/// How long a component's markup may run before its largest pieces are
/// pulled out into their own functions.
const reactLineBudget = 150;

class _ReactWriter {
  _ReactWriter(this.plan) {
    for (final s in plan.screens) {
      routes[s.file] = s.file == 'index.html' || plan.screens.first == s
          ? '/'
          : '/${s.file.replaceAll(RegExp(r'\.html?$'), '')}';
    }
    final names = <String>{};
    for (final s in plan.screens) {
      var n = pascal(s.title);
      if (n.isEmpty) n = 'Screen';
      var u = n;
      for (var i = 2; !names.add(u); i++) {
        u = '$n$i';
      }
      screenNames[s] = u;
    }
  }

  final DesignPlan plan;
  final routes = <String, String>{};
  final screenNames = <DScreen, String>{};
  final assets = <String>{};

  Map<String, String> files() {
    final out = <String, String>{};
    for (final s in plan.screens) {
      final name = screenNames[s]!;
      final parts = plan.parts[s]!;
      for (final p in parts) {
        // A part that is just a component's use is that component, placed.
        if (plan.componentOf(p.node) != null) continue;
        out['src/screens/$name/sections/${p.name}.tsx'] = _module(
          p.name,
          p.node,
          from: 'src/screens/$name/sections',
          partsOf: const {},
        );
      }
      out['src/screens/$name/$name.tsx'] = _screen(s, name, parts);
    }
    for (final c in plan.components) {
      out['src/components/${c.name}.tsx'] = _component(c);
    }
    out['src/theme.css'] = _theme();
    out['src/main.tsx'] = _main();
    out['index.html'] = _index();
    out['package.json'] = _package();
    out['tsconfig.json'] = _tsconfig;
    out['vite.config.ts'] = _vite;
    return out;
  }

  // ---- Files ------------------------------------------------------------------

  String _screen(DScreen s, String name, List<DPart> parts) {
    final partOf = {for (final p in parts) p.node: p};
    final ctx = _Ctx(from: 'src/screens/$name', partsOf: partOf);
    final body = s.body;
    final extra = _bodyStyleOf(s);
    final jsx = [for (final c in body.children) ..._jsx(c, ctx, 2)];
    final effects = <String>[
      if (s.pageTitle != null) 'document.title = ${jsonEncode(s.pageTitle)};',
      if (extra.isNotEmpty) 'Object.assign(document.body.style, ${_styleObject(extra)});',
    ];
    if (effects.isNotEmpty) ctx.react.add('useEffect');
    return [
      ..._imports(ctx),
      '',
      '/** ${s.title}: the screen, its parts in order. */',
      'export default function $name() {',
      if (effects.isNotEmpty) ...[
        '  useEffect(() => {',
        for (final e in effects) '    $e',
        '  }, []);',
      ],
      '  return (',
      '    <>',
      ...jsx.map((l) => '  $l'),
      '    </>',
      '  );',
      '}',
      '',
    ].join('\n');
  }

  String _module(
    String name,
    DNode node, {
    required String from,
    required Map<DNode, DPart> partsOf,
  }) {
    final ctx = _Ctx(from: from, partsOf: partsOf);
    final pieces = <String>[];
    final body = _budgeted(name, node, ctx, pieces);
    return [
      ..._imports(ctx),
      '',
      'export default function $name() {',
      '  return (',
      ...body.map((l) => '    $l'),
      '  );',
      '}',
      ...pieces,
      '',
    ].join('\n');
  }

  /// [node]'s markup, its largest pieces pulled out into functions of their
  /// own (added to [pieces]) while it runs past the budget.
  List<String> _budgeted(String name, DNode node, _Ctx ctx, List<String> pieces) {
    var lines = _jsx(node, ctx, 0);
    var n = 0;
    while (lines.length > reactLineBudget) {
      final biggest = _largestPiece(node, ctx);
      if (biggest == null) break;
      final piece = '$name${pascal(biggest.tag ?? 'piece')}${++n}';
      ctx.pieces[biggest] = piece;
      final inner = _jsx(biggest, ctx.without(biggest), 0);
      pieces.addAll([
        '',
        'function $piece() {',
        '  return (',
        ...inner.map((l) => '    $l'),
        '  );',
        '}',
      ]);
      lines = _jsx(node, ctx, 0);
    }
    return lines;
  }

  /// The largest element under [root] not already pulled out, a part, or a
  /// component's use.
  DNode? _largestPiece(DNode root, _Ctx ctx) {
    DNode? best;
    for (final d in root.descendants) {
      if (d.isText || d.tag == 'svg') continue;
      if (ctx.pieces.containsKey(d) || ctx.partsOf.containsKey(d) || plan.componentOf(d) != null)
        continue;
      if (d.ancestors.any((a) => ctx.pieces.containsKey(a) || plan.componentOf(a) != null))
        continue;
      if (best == null || d.size > best.size) best = d;
    }
    return best != null && best.size > 3 ? best : null;
  }

  String _component(DComponent c) {
    final ctx = _Ctx(from: 'src/components', partsOf: const {}, component: c);
    final jsx = _jsx(c.model, ctx, 0, rootOfComponent: true);
    final props = c.params.isEmpty
        ? ''
        : '{ ${c.params.map((p) => p.name).join(', ')} }: { ${c.params.map((p) => '${p.name}: ${p.kind == DParamKind.element ? 'ReactNode' : 'string'}').join('; ')} }';
    if (c.params.any((p) => p.kind == DParamKind.element)) ctx.reactTypes.add('ReactNode');
    return [
      ..._imports(ctx),
      '',
      '/** Used ${c.uses.length} times${c.params.isEmpty ? ', the same each time' : ''}. */',
      'export default function ${c.name}($props) {',
      '  return (',
      ...jsx.map((l) => '    $l'),
      '  );',
      '}',
      '',
    ].join('\n');
  }

  List<String> _imports(_Ctx ctx) => [
    if (ctx.react.isNotEmpty || ctx.reactTypes.isNotEmpty)
      "import { ${[...ctx.react.toList()..sort(), ...ctx.reactTypes.map((t) => 'type $t')].join(', ')} } from 'react';",
    if (ctx.router) "import { Link } from 'react-router-dom';",
    for (final i in (ctx.imports.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
      "import ${i.key} from '${i.value}';",
  ];

  // ---- Markup ---------------------------------------------------------------

  List<String> _jsx(DNode n, _Ctx ctx, int indent, {bool rootOfComponent = false}) {
    final pad = '  ' * indent;
    if (n.isText) {
      if (ctx.paramAt(n, DParamKind.text) case final p?) return ['$pad{${p.name}}'];
      if (n.text!.trim().isEmpty && _unseen(n)) return const [];
      return ['$pad${_text(n.text!)}'];
    }
    // A part of the screen, a piece pulled out, a component's use: by name.
    if (ctx.partsOf[n] case final part?) {
      final c = plan.componentOf(n);
      if (c != null) return ['$pad${_use(c, n, ctx)}'];
      ctx.imports[part.name] = _rel(
        ctx.from,
        'src/screens/${screenNames[part.screen]}/sections/${part.name}',
      );
      return ['$pad<${part.name} />'];
    }
    if (ctx.pieces[n] case final piece?) return ['$pad<$piece />'];
    if (!rootOfComponent) {
      final c = plan.componentOf(n);
      if (c != null && c != ctx.component) return ['$pad${_use(c, n, ctx)}'];
    }
    // A parameter standing for this whole element (an icon).
    if (ctx.paramAt(n, DParamKind.element) case final p?) return ['$pad{${p.name}}'];

    final tag = n.tag!;
    final internal =
        tag == 'a' &&
        _route(n.attrs['href']) != null &&
        ctx.paramAt(n, DParamKind.attr, 'href') == null;
    final name = internal ? 'Link' : tag;
    if (internal) ctx.router = true;
    final attrs = <String>[
      for (final e in n.attrs.entries) _attr(n, e.key, e.value, ctx, internal: internal),
      if (n.classes.isNotEmpty) 'className=${jsonEncode(n.classes.join(' '))}',
      if (n.style.isNotEmpty) 'style={${_styleObject(n.style)}}',
    ];
    final open = attrs.isEmpty ? '<$name' : '<$name ${attrs.join(' ')}';
    if (_void.contains(tag) || n.children.isEmpty) return ['$pad$open />'];
    final kids = [for (final c in n.children) ..._jsx(c, ctx, indent + 1)];
    // Short and on one line where it fits.
    if (kids.length == 1 &&
        kids.first.trim().length + open.length < 90 &&
        !kids.first.trim().startsWith('<')) {
      return ['$pad$open>${kids.first.trim()}</$name>'];
    }
    return ['$pad$open>', ...kids, '$pad</$name>'];
  }

  String _attr(DNode n, String key, String value, _Ctx ctx, {required bool internal}) {
    final p = ctx.paramAt(n, DParamKind.attr, key);
    final name = key == 'href' && internal
        ? 'to'
        : _attrName(key, svg: n.tag == 'svg' || n.ancestors.any((a) => a.tag == 'svg'));
    if (p != null) return '$name={${p.name}}';
    var v = value;
    if (key == 'href') v = internal ? _route(value)! : _asset(value);
    if (key == 'src' || key == 'srcset' || key == 'poster') v = _asset(value);
    return '$name=${jsonEncode(v)}';
  }

  String _use(DComponent c, DNode use, _Ctx ctx) {
    ctx.imports[c.name] = _rel(ctx.from, 'src/components/${c.name}');
    final args = c.argsOf(use);
    final props = <String>[];
    for (final p in c.params) {
      // Inside a component, a value that is one of its own parameters goes on.
      final own = ctx.paramAt(_nodeAt(use, p.path), p.kind, p.attr);
      if (own != null) {
        props.add('${p.name}={${own.name}}');
        continue;
      }
      final v = args[p.name]!;
      switch (p.kind) {
        case DParamKind.text:
          props.add('${p.name}=${jsonEncode(v)}');
        case DParamKind.attr:
          final s = v as String;
          props.add(
            '${p.name}=${jsonEncode(p.attr == 'href' ? (_route(s) ?? _asset(s)) : (p.attr == 'src' ? _asset(s) : s))}',
          );
        case DParamKind.element:
          props.add(
            '${p.name}={${_jsx(v as DNode, ctx.inUse(), 0).join(' ').replaceAll(RegExp(r'\s+'), ' ')}}',
          );
      }
    }
    return props.isEmpty ? '<${c.name} />' : '<${c.name} ${props.join(' ')} />';
  }

  /// Space a browser never draws: between a flex or grid's items, or
  /// between blocks or at a block's edges. Left out, the page is the same.
  static bool _unseen(DNode space) {
    final parent = space.parent;
    if (parent == null) return true;
    final display = parent.style['display'] ?? '';
    if (display.contains('flex') || display.contains('grid')) return true;
    if (!_blockish(parent)) return false;
    final i = parent.children.indexOf(space);
    final before = i > 0 ? parent.children[i - 1] : null;
    final after = i + 1 < parent.children.length ? parent.children[i + 1] : null;
    return (before == null || _blockish(before)) && (after == null || _blockish(after));
  }

  static bool _blockish(DNode n) {
    if (n.isText) return false;
    final display = n.style['display'];
    if (display != null) return !display.startsWith('inline') && display != 'contents';
    if ((n.style['position'] == 'absolute' || n.style['position'] == 'fixed')) return true;
    return const {
      'address',
      'article',
      'aside',
      'blockquote',
      'body',
      'dd',
      'details',
      'dialog',
      'div',
      'dl',
      'dt', //
      'fieldset',
      'figcaption',
      'figure',
      'footer',
      'form',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'header',
      'hr', 'li', 'main', 'nav', 'ol', 'p', 'pre', 'section', 'summary', 'table', 'ul',
    }.contains(n.tag);
  }

  static DNode _nodeAt(DNode root, List<int> path) {
    var n = root;
    for (final i in path) {
      n = n.children[i];
    }
    return n;
  }

  String _text(String t) {
    if (t.trim().isEmpty) return "{' '}";
    // Written as an expression when JSX would read it otherwise: braces,
    // angle brackets, or space at an end that JSX would drop.
    if (RegExp(r'[{}<>&]').hasMatch(t) || t != t.trim()) return '{${jsonEncode(t)}}';
    return t;
  }

  String _styleObject(Map<String, String> style) {
    final entries = [
      for (final e in style.entries)
        '${_styleKey(e.key)}: ${jsonEncode(_tokenized(e.key, e.value))}',
    ];
    return '{ ${entries.join(', ')} }';
  }

  /// A color or font the theme names, as its variable: the same value.
  String _tokenized(String prop, String value) {
    if (prop == 'font-family') {
      final t = plan.tokenFor(value);
      return t == null ? value : 'var(--${t.name})';
    }
    return value.replaceAllMapped(RegExp(r'#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\)'), (
      m,
    ) {
      final t = plan.tokenFor(m[0]!.replaceAll(' ', ''));
      return t == null ? m[0]! : 'var(--${t.name})';
    });
  }

  static String _styleKey(String prop) {
    if (prop.startsWith('--')) return jsonEncode(prop);
    final vendor = prop.startsWith('-');
    final parts = (vendor ? prop.substring(1) : prop).split('-');
    final key = [
      parts.first,
      for (final p in parts.skip(1)) p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}',
    ].join();
    // -webkit-x is WebkitX; -ms-x stays msX, as React has it.
    if (vendor && !prop.startsWith('-ms-')) return '${key[0].toUpperCase()}${key.substring(1)}';
    return key;
  }

  static String _attrName(String key, {required bool svg}) {
    const named = {
      'class': 'className',
      'for': 'htmlFor',
      'tabindex': 'tabIndex',
      'readonly': 'readOnly',
      'maxlength': 'maxLength',
      'crossorigin': 'crossOrigin',
      'srcset': 'srcSet',
      'autocomplete': 'autoComplete',
      'autofocus': 'autoFocus',
      'colspan': 'colSpan',
      'rowspan': 'rowSpan',
      'datetime': 'dateTime',
      'xlink:href': 'xlinkHref',
      'xml:space': 'xmlSpace',
      'xmlns:xlink': 'xmlnsXlink',
      'viewbox': 'viewBox',
    };
    if (named[key] case final n?) return n;
    if (key.startsWith('data-') || key.startsWith('aria-')) return key;
    if (svg && key.contains('-')) {
      final parts = key.split('-');
      return [
        parts.first,
        for (final p in parts.skip(1)) '${p[0].toUpperCase()}${p.substring(1)}',
      ].join();
    }
    return key;
  }

  /// A link to another screen, as its route; null for any other link.
  String? _route(String? href) {
    if (href == null || href.contains(':') || href.startsWith('//')) return null;
    final hash = href.indexOf('#');
    final file = hash < 0 ? href : href.substring(0, hash);
    final fragment = hash < 0 ? '' : href.substring(hash);
    final route = routes[file.replaceFirst(RegExp(r'^\./'), '')];
    if (route == null) return file.isEmpty && fragment.isNotEmpty ? null : null;
    return '$route$fragment';
  }

  /// A file of the design's (`img/a.png`), as `public/` serves it.
  String _asset(String value) {
    if (value.isEmpty || value.contains(':') || value.startsWith('//') || value.startsWith('#'))
      return value;
    final clean = value.replaceFirst(RegExp(r'^\./'), '').split('?').first;
    if (clean.startsWith('/')) return value;
    assets.add(clean);
    return '/$clean';
  }

  String _rel(String from, String to) {
    final a = from.split('/'), b = to.split('/');
    var i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    final up = a.length - i;
    final rest = b.sublist(i).join('/');
    return up == 0 ? './$rest' : '${'../' * up}$rest';
  }

  // ---- The project around it --------------------------------------------------

  /// The body's style that screens share goes in the stylesheet; what one
  /// screen has of its own, it sets when it shows.
  Map<String, String> get _sharedBody {
    final first = plan.screens.first.body.style;
    return {
      for (final e in first.entries)
        if (plan.screens.every((s) => s.body.style[e.key] == e.value)) e.key: e.value,
    };
  }

  Map<String, String> _bodyStyleOf(DScreen s) {
    final shared = _sharedBody;
    return {
      for (final e in s.body.style.entries)
        if (shared[e.key] != e.value) e.key: e.value,
    };
  }

  String _theme() {
    final css = <String>{
      for (final s in plan.screens)
        if (s.css.isNotEmpty) s.css,
    };
    return [
      '/* The design\'s colors and fonts, named; the pages use these names. */',
      ':root {',
      for (final t in plan.tokens) '  --${t.name}: ${t.value};',
      '}',
      '',
      'body {',
      for (final e in _sharedBody.entries) '  ${e.key}: ${_tokenized(e.key, e.value)};',
      '}',
      if (css.isNotEmpty) ...['', '/* As the design wrote it. */', ...css],
      '',
    ].join('\n');
  }

  String _main() => [
    "import { StrictMode } from 'react';",
    "import { createRoot } from 'react-dom/client';",
    "import { BrowserRouter, Route, Routes } from 'react-router-dom';",
    "import './theme.css';",
    for (final s in plan.screens)
      "import ${screenNames[s]} from './screens/${screenNames[s]}/${screenNames[s]}';",
    '',
    "createRoot(document.getElementById('root')!).render(",
    '  <StrictMode>',
    '    <BrowserRouter>',
    '      <Routes>',
    for (final s in plan.screens)
      '        <Route path="${routes[s.file]}" element={<${screenNames[s]} />} />',
    '      </Routes>',
    '    </BrowserRouter>',
    '  </StrictMode>,',
    ');',
    '',
  ].join('\n');

  String _index() {
    final links = <String>{for (final s in plan.screens) ...s.links};
    return [
      '<!doctype html>',
      '<html lang="en">',
      '<head>',
      '<meta charset="utf-8">',
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
      '<title>${const HtmlEscape().convert(plan.screens.first.pageTitle ?? plan.title)}</title>',
      ...links,
      '</head>',
      '<body>',
      '<div id="root"></div>',
      '<script type="module" src="/src/main.tsx"></script>',
      '</body>',
      '</html>',
      '',
    ].join('\n');
  }

  String _package() {
    final name = plan.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '${const JsonEncoder.withIndent('  ').convert({
      'name': name.isEmpty ? 'design' : name,
      'private': true,
      'version': '0.0.0',
      'type': 'module',
      'scripts': {'dev': 'vite', 'build': 'tsc -b && vite build', 'preview': 'vite preview'},
      'dependencies': {'react': '^19.1.0', 'react-dom': '^19.1.0', 'react-router-dom': '^7.6.0'},
      'devDependencies': {'@types/react': '^19.1.0', '@types/react-dom': '^19.1.0', '@vitejs/plugin-react': '^4.5.0', 'typescript': '^5.8.0', 'vite': '^6.3.0'},
    })}\n';
  }

  static const _tsconfig = '''{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
''';

  static const _vite = '''import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({ plugins: [react()] });
''';

  static const _void = {
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'source',
    'track',
    'wbr', //
  };
}

/// What one file's markup has gathered as it was written: its imports,
/// pieces pulled out, and the component it is, if it is one.
class _Ctx {
  _Ctx({required this.from, required this.partsOf, this.component});
  final String from;
  final Map<DNode, DPart> partsOf;
  final DComponent? component;
  final imports = <String, String>{};
  final react = <String>{};
  final reactTypes = <String>{};
  final pieces = <DNode, String>{};
  bool router = false;

  /// For writing a pulled-out piece: the same file, the piece itself drawn.
  _Ctx without(DNode piece) => _Sub(this, piece);

  /// For an argument's markup: no component parameters apply there.
  _Ctx inUse() => _Sub(this, null, noParams: true);

  /// The parameter of [component] at [n], of [kind] (and [attr]).
  DParam? paramAt(DNode n, DParamKind kind, [String? attr]) {
    final c = component;
    if (c == null) return null;
    final path = <int>[];
    var at = n;
    while (!identical(at, c.model)) {
      final p = at.parent;
      if (p == null) return null;
      path.insert(0, p.children.indexOf(at));
      at = p;
    }
    for (final p in c.params) {
      if (p.kind == kind && p.attr == attr && _same(p.path, path)) return p;
    }
    return null;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _Sub extends _Ctx {
  _Sub(this.outer, this.drawing, {this.noParams = false})
    : super(from: outer.from, partsOf: outer.partsOf, component: outer.component);
  final _Ctx outer;
  final DNode? drawing;
  final bool noParams;

  @override
  Map<String, String> get imports => outer.imports;
  @override
  Set<String> get react => outer.react;
  @override
  Set<String> get reactTypes => outer.reactTypes;
  @override
  Map<DNode, String> get pieces => {
    for (final e in outer.pieces.entries)
      if (!identical(e.key, drawing)) e.key: e.value,
  };
  @override
  bool get router => outer.router;
  @override
  set router(bool v) => outer.router = v;
  @override
  DParam? paramAt(DNode n, DParamKind kind, [String? attr]) =>
      noParams ? null : outer.paramAt(n, kind, attr);
}
