import 'design_model.dart';

/// Cuts a design up where it already is: each screen into its parts, what
/// repeats into components with parameters, and the values it reuses into
/// tokens. Deterministic: the same design gives the same plan, names and all.
DesignPlan planDesign({required String title, required List<DScreen> screens}) {
  final parts = {for (final s in screens) s: _partsOf(s)};
  final components = _components(screens, parts);
  return DesignPlan(
    title: title,
    screens: screens,
    parts: parts,
    components: components,
    tokens: _tokens(screens),
  );
}

// ---- Parts --------------------------------------------------------------------

const _landmarks = {'header', 'nav', 'section', 'footer', 'aside', 'article'};

bool _isPart(DNode n) =>
    !n.isText && (_landmarks.contains(n.tag) || (n.attrs['id'] ?? '').isNotEmpty);

/// The landmarks and elements with an id, from the top: a wrapper around
/// them (main, a div) is looked into, and what is not in one stays with the
/// screen itself.
List<DPart> _partsOf(DScreen s) {
  final found = <DNode>[];
  void walk(DNode n) {
    for (final c in n.children) {
      if (c.isText) continue;
      if (_isPart(c)) {
        found.add(c);
      } else if (c.descendants.any(_isPart)) {
        walk(c);
      }
    }
  }

  walk(s.body);
  final names = <String>{};
  return [
    for (final (i, n) in found.indexed)
      DPart(name: _unique(names, _partName(n, s, i)), node: n, screen: s),
  ];
}

String _partName(DNode n, DScreen s, int i) {
  final id = n.attrs['id'];
  if (id != null && id.isNotEmpty) return _withSuffix(pascal(id), n);
  final label = n.attrs['aria-label'];
  if (label != null && label.isNotEmpty) return _withSuffix(pascal(label), n);
  switch (n.tag) {
    case 'header':
      return 'Header';
    case 'footer':
      return 'Footer';
    case 'nav':
      return 'Nav';
  }
  final heading = n.descendants.where((d) => RegExp(r'^h[1-6]$').hasMatch(d.tag ?? '')).firstOrNull;
  final words = heading?.words.split(' ').where((w) => w.isNotEmpty).take(3).join(' ');
  if (words != null && pascal(words).isNotEmpty) return _withSuffix(pascal(words), n);
  return '${pascal(s.title)}Section${i + 1}';
}

String _withSuffix(String name, DNode n) =>
    n.tag == 'section' && !name.endsWith('Section') ? '${name}Section' : name;

// ---- Components ---------------------------------------------------------------

/// Attributes that are what a use says, not how it is built: they may
/// differ between uses of one component.
const contentAttrs = {
  'href',
  'src',
  'srcset',
  'alt',
  'title',
  'aria-label',
  'datetime',
  'value',
  'placeholder',
  'id',
};

/// A tree's structure and styling, without its words, links or icons: two
/// parts with the same signature are one component.
String _signature(DNode n, Map<DNode, String> memo) {
  final known = memo[n];
  if (known != null) return known;
  final String sig;
  if (n.isText) {
    sig = 'T';
  } else if (n.tag == 'svg') {
    // An icon is one thing, which may differ between uses.
    sig =
        'svg[${n.attrs['width']}x${n.attrs['height']}|${_styleKey(n.style)}|${n.classes.join('.')}]';
  } else {
    final attrs = [
      for (final e in n.attrs.entries)
        if (!contentAttrs.contains(e.key)) '${e.key}=${e.value}',
    ]..sort();
    sig =
        '${n.tag}[${n.classes.join('.')}|${_styleKey(n.style)}|${attrs.join(',')}]'
        '(${n.children.map((c) => _signature(c, memo)).join(',')})';
  }
  return memo[n] = sig;
}

String _styleKey(Map<String, String> style) =>
    (style.entries.map((e) => '${e.key}:${e.value}').toList()..sort()).join(';');

int _weight(DNode n) =>
    n.isText ? 0 : (n.tag == 'svg' ? 1 : 1 + n.children.fold(0, (a, c) => a + _weight(c)));

List<DComponent> _components(List<DScreen> screens, Map<DScreen, List<DPart>> parts) {
  final memo = <DNode, String>{};
  final groups = <String, List<DNode>>{};
  for (final s in screens) {
    for (final n in s.body.descendants) {
      if (n.isText || n.tag == 'svg') continue;
      // Worth a component: a few elements at least.
      if (_weight(n) < 3) continue;
      (groups[_signature(n, memo)] ??= []).add(n);
    }
  }
  // Largest first, so a card is chosen before the badge inside it.
  final repeated = groups.values.where((uses) => uses.length > 1).toList()
    ..sort((a, b) {
      final w = _weight(b.first).compareTo(_weight(a.first));
      return w != 0 ? w : _signature(a.first, memo).compareTo(_signature(b.first, memo));
    });
  final chosen = <DNode>{};
  final out = <({List<DNode> uses})>[];
  for (final uses in repeated) {
    // Only part of a component already chosen, once in each use of it:
    // that component already says it.
    final within = [for (final u in uses) u.ancestors.where(chosen.contains).firstOrNull];
    if (within.every((a) => a != null) && within.toSet().length == uses.length) continue;
    chosen.addAll(uses);
    out.add((uses: uses));
  }
  final names = <String>{};
  final partOf = <DNode, DPart>{
    for (final list in parts.values)
      for (final p in list) p.node: p,
  };
  return [
    for (final c in out)
      DComponent(
        name: _unique(names, _componentName(c.uses, partOf, screens)),
        uses: c.uses,
        params: _params(c.uses),
      ),
  ];
}

String _componentName(List<DNode> uses, Map<DNode, DPart> partOf, List<DScreen> screens) {
  final n = uses.first;
  final useful = n.classes.where((c) => !_utility.hasMatch(c)).toList();
  if (useful.isNotEmpty) return pascal(useful.first);
  // All a landmark holds (the header's one row): named for the landmark.
  final holder = n.parent;
  final only = holder != null && holder.children.where((c) => !c.isText).length == 1;
  final landmark = only
      ? const {'header': 'Header', 'footer': 'Footer', 'nav': 'Nav'}[holder.tag]
      : null;
  final kind =
      landmark ??
      switch (n.tag) {
        'header' => 'Header',
        'footer' => 'Footer',
        'nav' => 'Nav',
        'a' => 'Link',
        'button' => 'Button',
        'li' => 'Item',
        'section' => 'Section',
        _ when n.descendants.any((d) => RegExp(r'^h[1-6]$').hasMatch(d.tag ?? '')) => 'Card',
        _ when n.descendants.any((d) => d.tag == 'img') => 'Picture',
        _ => 'Block',
      };
  // Named for where its uses are: the one part they are all in, else the
  // one screen, else the site.
  DPart? partAround(DNode u) => [u, ...u.ancestors].map((a) => partOf[a]).nonNulls.firstOrNull;
  final inParts = {for (final u in uses) partAround(u)};
  final onScreens = {for (final u in uses) partAround(u)?.screen};
  final String prefix;
  if (inParts.length == 1 && inParts.first != null && !identical(inParts.first!.node, n)) {
    prefix = inParts.first!.name.replaceAll(RegExp(r'Section$'), '');
  } else if (onScreens.length == 1 && onScreens.first != null) {
    prefix = pascal(onScreens.first!.title);
  } else {
    prefix = 'Site';
  }
  return prefix == kind ? kind : '$prefix$kind';
}

/// Class names that say how, not what: `hide-sm`, `flex`, `p-4`.
final _utility = RegExp(
  r'^(hide|show|flip|art|sm|md|lg|xl|p|m|px|py|mx|my|flex|grid|gap|w|h|text|bg)(-|$)',
);

/// Where [uses] differ: each such place a parameter, named by what it is.
List<DParam> _params(List<DNode> uses) {
  final out = <DParam>[];
  final names = <String>{};
  void walk(List<DNode> at, List<int> path) {
    final n = at.first;
    if (n.isText) {
      if (at.any((u) => u.text != n.text)) {
        out.add(DParam(name: _unique(names, _textName(n)), kind: DParamKind.text, path: path));
      }
      return;
    }
    if (n.tag == 'svg') {
      final html = at.map(_markup).toSet();
      if (html.length > 1) {
        out.add(DParam(name: _unique(names, 'icon'), kind: DParamKind.element, path: path));
      }
      return;
    }
    final keys = {for (final u in at) ...u.attrs.keys}.where(contentAttrs.contains).toList()
      ..sort();
    for (final k in keys) {
      if (at.map((u) => u.attrs[k] ?? '').toSet().length > 1) {
        out.add(
          DParam(name: _unique(names, _attrName(k)), kind: DParamKind.attr, path: path, attr: k),
        );
      }
    }
    for (var i = 0; i < n.children.length; i++) {
      walk([for (final u in at) u.children[i]], [...path, i]);
    }
  }

  walk(uses, const []);
  return out;
}

String _textName(DNode n) {
  for (final a in n.ancestors) {
    final t = a.tag ?? '';
    if (RegExp(r'^h[1-6]$').hasMatch(t)) return 'title';
    if (t == 'a' || t == 'button') return 'label';
    if (t == 'p') return 'text';
  }
  return 'text';
}

String _attrName(String attr) => switch (attr) {
  'href' => 'href',
  'src' => 'image',
  'srcset' => 'imageSet',
  'alt' => 'alt',
  'aria-label' => 'label',
  _ => camel(attr),
};

/// [n] as markup, for telling icons apart.
String _markup(DNode n) => n.isText
    ? n.text!
    : '<${n.tag} ${n.attrs.entries.map((e) => '${e.key}="${e.value}"').join(' ')} '
          '${_styleKey(n.style)}>${n.children.map(_markup).join()}</${n.tag}>';

// ---- Tokens -------------------------------------------------------------------

final _color = RegExp(r'#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\)');

List<DToken> _tokens(List<DScreen> screens) {
  final colorUses = <String, Map<String, int>>{}; // value -> role -> count
  final fontUses = <String, int>{};
  for (final s in screens) {
    for (final n in [s.body, ...s.body.descendants]) {
      for (final e in n.style.entries) {
        if (e.key == 'font-family') {
          fontUses[e.value] = (fontUses[e.value] ?? 0) + 1;
          continue;
        }
        for (final m in _color.allMatches(e.value)) {
          final v = m[0]!.toLowerCase().replaceAll(' ', '');
          final role = _role(e.key);
          final roles = colorUses[v] ??= {};
          roles[role] = (roles[role] ?? 0) + 1;
        }
      }
    }
  }
  final out = <DToken>[];
  // Colors: each by the role it plays most, numbered by how much it is used.
  final byRole = <String, List<(String, int)>>{};
  for (final e in colorUses.entries) {
    final total = e.value.values.fold(0, (a, b) => a + b);
    if (total < 2) continue;
    final role =
        (e.value.entries.toList()..sort(
              (a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key),
            ))
            .first
            .key;
    (byRole[role] ??= []).add((e.key, total));
  }
  for (final role in byRole.keys.toList()..sort()) {
    final list = byRole[role]!
      ..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
    for (final (i, (value, uses)) in list.indexed) {
      out.add(
        DToken(
          name: i == 0 ? role : '$role${i + 1}',
          value: value,
          kind: DTokenKind.color,
          uses: uses,
        ),
      );
    }
  }
  // Fonts: the page's own (the body's) first, then by how much each is used.
  final body = screens.map((s) => s.body.style['font-family']).nonNulls.firstOrNull;
  final fonts = fontUses.entries.toList()
    ..sort((a, b) {
      if ((a.key == body) != (b.key == body)) return a.key == body ? -1 : 1;
      return b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key);
    });
  for (final (i, e) in fonts.indexed) {
    out.add(
      DToken(
        name: switch (i) {
          0 => 'fontBody',
          1 => 'fontDisplay',
          _ => 'font${i + 1}',
        },
        value: e.key,
        kind: DTokenKind.font,
        uses: e.value,
      ),
    );
  }
  return out;
}

String _role(String prop) => switch (prop) {
  'background' || 'background-color' || 'background-image' => 'surface',
  'color' || '-webkit-text-fill-color' || 'caret-color' => 'text',
  'fill' || 'stroke' => 'icon',
  'box-shadow' || 'text-shadow' || 'filter' => 'shadow',
  _ when prop.startsWith('border') || prop.startsWith('outline') => 'border',
  _ => 'accent',
};

// ---- Names --------------------------------------------------------------------

/// "how it works" -> "HowItWorks"; never starting with a digit.
String pascal(String text) {
  final words = text
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty);
  final joined = words.map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join();
  return joined.replaceFirst(RegExp(r'^[0-9]+'), '');
}

String camel(String text) {
  final p = pascal(text);
  return p.isEmpty ? p : '${p[0].toLowerCase()}${p.substring(1)}';
}

String _unique(Set<String> taken, String name) {
  var n = name.isEmpty ? 'Part' : name;
  var i = 2;
  while (!taken.add(n)) {
    n = '$name${i++}';
  }
  return n;
}
