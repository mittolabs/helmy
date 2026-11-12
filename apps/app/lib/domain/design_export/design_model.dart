/// A design as the converter reads it: its screens, each a tree of nodes, the
/// parts every screen is cut into, the components that repeat, and the
/// theme. Built once from the design's files ([readDesign] and [planDesign]),
/// and written out by each target (React, Flutter) the same way every time.
library;

/// One node of a screen: an element, or a run of text.
class DNode {
  DNode.element(
    this.tag, {
    Map<String, String>? attrs,
    Map<String, String>? style,
    List<String>? classes,
    List<DNode>? children,
  }) : text = null,
       attrs = attrs ?? {},
       style = style ?? {},
       classes = classes ?? [],
       children = children ?? [];

  DNode.text(String this.text)
    : tag = null,
      attrs = const {},
      style = const {},
      classes = const [],
      children = const [];

  /// Lower case; null for text.
  final String? tag;
  final String? text;

  /// Its attributes but `style` and `class`, in the order written.
  final Map<String, String> attrs;

  /// Its inline style, property by property, in the order written.
  final Map<String, String> style;
  final List<String> classes;
  final List<DNode> children;

  /// Where it sits, set once the tree is read: its parent, null at the top.
  DNode? parent;

  /// Its place among its parent's elements in the page as written (from 1,
  /// counting those the converter leaves out, like scripts): for finding it
  /// again in the page with `:nth-child`.
  int nth = 1;

  /// How the page finds it: `body > div:nth-child(2) > a:nth-child(1)`.
  String get selector {
    if (isText) return parent?.selector ?? 'body';
    if (parent == null) return tag!;
    return '${parent!.selector} > $tag:nth-child($nth)';
  }

  bool get isText => tag == null;

  /// Elements in this subtree, itself included.
  int get size => isText ? 0 : 1 + children.fold(0, (n, c) => n + c.size);

  Iterable<DNode> get descendants sync* {
    for (final c in children) {
      yield c;
      yield* c.descendants;
    }
  }

  Iterable<DNode> get ancestors sync* {
    for (var p = parent; p != null; p = p.parent) {
      yield p;
    }
  }

  /// Its words, as a person reads them: whitespace run together.
  String get words => isText
      ? text!.replaceAll(RegExp(r'\s+'), ' ').trim()
      : children.map((c) => c.words).where((w) => w.isNotEmpty).join(' ');
}

/// One screen of the design: a page in its folder.
class DScreen {
  DScreen({
    required this.file,
    required this.title,
    required this.body,
    required this.css,
    required this.links,
    this.pageTitle,
  });

  /// Its file in the design folder, `download.html`.
  final String file;

  /// Its name on the canvas, "Download".
  final String title;

  /// The page's own title, in its head.
  final String? pageTitle;

  /// The page's body.
  final DNode body;

  /// What its `<style>` blocks say, as written.
  final String css;

  /// Its stylesheet links (fonts), as written.
  final List<String> links;
}

/// A part a screen is cut into: a landmark (header, section, footer) or an
/// element with an id. A screen's file only places its parts.
class DPart {
  DPart({required this.name, required this.node, required this.screen});
  final String name;
  final DNode node;
  final DScreen screen;
}

/// What differs between a component's uses: text, an attribute, or a
/// whole element (an icon), at one place in its tree.
class DParam {
  DParam({required this.name, required this.kind, required this.path, this.attr});
  final String name;
  final DParamKind kind;

  /// Child indexes from the component's root down to where it is.
  final List<int> path;

  /// The attribute, for [DParamKind.attr].
  final String? attr;
}

enum DParamKind { text, attr, element }

/// A part that repeats with the same structure and styling, only its text,
/// images or links differing: one component, with a parameter for each
/// difference, used wherever it occurs (across screens too).
class DComponent {
  DComponent({required this.name, required this.uses, required this.params});
  final String name;

  /// Every place it occurs, the first being the one it is written from.
  final List<DNode> uses;
  final List<DParam> params;

  DNode get model => uses.first;

  /// What [use] gives each parameter.
  Map<String, Object> argsOf(DNode use) => {for (final p in params) p.name: _at(use, p)};

  static Object _at(DNode use, DParam p) {
    var n = use;
    for (final i in p.path) {
      n = n.children[i];
    }
    return switch (p.kind) {
      DParamKind.text => n.text!,
      DParamKind.attr => n.attrs[p.attr] ?? '',
      DParamKind.element => n,
    };
  }
}

/// A value the design uses more than once, named: a color or a font.
class DToken {
  DToken({required this.name, required this.value, required this.kind, required this.uses});
  final String name;
  final String value;
  final DTokenKind kind;
  final int uses;
}

enum DTokenKind { color, font }

/// The whole design, cut up: what every target writes out.
class DesignPlan {
  DesignPlan({
    required this.title,
    required this.screens,
    required this.parts,
    required this.components,
    required this.tokens,
  });

  final String title;
  final List<DScreen> screens;

  /// Each screen's parts, in the order they appear.
  final Map<DScreen, List<DPart>> parts;
  final List<DComponent> components;
  final List<DToken> tokens;

  /// The component [node] is a use of, if any.
  DComponent? componentOf(DNode node) {
    for (final c in components) {
      if (c.uses.any((u) => identical(u, node))) return c;
    }
    return null;
  }

  /// The token for [value], if the design names it.
  DToken? tokenFor(String value) {
    final v = value.trim().toLowerCase();
    for (final t in tokens) {
      if (t.value.toLowerCase() == v) return t;
    }
    return null;
  }
}
