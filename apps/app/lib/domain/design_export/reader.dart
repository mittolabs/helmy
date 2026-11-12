import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'design_model.dart';

/// The design in [folder] (its `canvas.json` and a page per screen), read
/// into trees: the screens in the canvas's order, named as it names them.
Future<({String title, List<DScreen> screens})> readDesign(String folder) async {
  final index = jsonDecode(await File('$folder/canvas.json').readAsString()) as Map;
  final boards = (index['boards'] as Map? ?? const {}).cast<String, Object?>();
  final order = [
    for (final f in (index['order'] as List? ?? boards.keys.toList()))
      if (boards.containsKey(f)) '$f',
  ];
  final screens = <DScreen>[];
  for (final file in order) {
    final page = File('$folder/$file');
    if (!page.existsSync()) continue;
    final b = (boards[file] as Map?) ?? const {};
    screens.add(
      readScreen(
        file,
        await page.readAsString(),
        title: b['title'] as String? ?? file.replaceAll(RegExp(r'\.html?$'), ''),
      ),
    );
  }
  return (title: '${index['title'] ?? 'Design'}', screens: screens);
}

/// One page, read: its body as a tree, its styles and its stylesheet links.
DScreen readScreen(String file, String source, {required String title}) {
  final doc = html.parse(source);
  final css = [for (final s in doc.querySelectorAll('style')) s.text.trim()].join('\n\n');
  final links = [
    for (final l in doc.querySelectorAll('link[rel="stylesheet"]')) l.outerHtml,
  ];
  final body = _node(doc.body!, preformatted: false)!;
  _link(body, null);
  return DScreen(
    file: file,
    title: title,
    pageTitle: doc.querySelector('title')?.text.trim(),
    body: body,
    css: css,
    links: links,
  );
}

void _link(DNode n, DNode? parent) {
  n.parent = parent;
  for (final c in n.children) {
    _link(c, n);
  }
}

DNode? _node(dom.Node n, {required bool preformatted}) {
  if (n is dom.Text) {
    final t = n.text;
    if (preformatted) return DNode.text(t);
    // Whitespace collapses in a page: a run of it reads the same as one
    // space, so written as one it draws the same.
    final collapsed = t.replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.isEmpty ? null : DNode.text(collapsed);
  }
  if (n is! dom.Element) return null;
  final tag = n.localName!.toLowerCase();
  if (tag == 'script' || tag == 'style' || tag == 'template') return null;
  final style = parseStyle(n.attributes['style'] ?? '');
  final pre =
      preformatted ||
      tag == 'pre' ||
      tag == 'textarea' ||
      (style['white-space']?.startsWith('pre') ?? false);
  final children = <DNode>[];
  var nth = 0;
  for (final c in n.nodes) {
    if (c is dom.Element) nth++;
    final d = _node(c, preformatted: pre);
    if (d == null) continue;
    if (!d.isText) d.nth = nth;
    children.add(d);
  }
  return DNode.element(
    tag,
    attrs: {
      for (final e in n.attributes.entries)
        if (e.key != 'style' && e.key != 'class') '${e.key}': e.value,
    },
    style: style,
    classes: (n.attributes['class'] ?? '').split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList(),
    children: children,
  );
}

/// An inline style, property by property: `a:b;c:url(x;y)` read with its
/// brackets and quotes kept whole.
Map<String, String> parseStyle(String text) {
  final out = <String, String>{};
  var depth = 0;
  String? quote;
  var start = 0;
  void take(int end) {
    final decl = text.substring(start, end);
    final colon = decl.indexOf(':');
    if (colon > 0) {
      final prop = decl.substring(0, colon).trim().toLowerCase();
      final value = decl.substring(colon + 1).trim();
      if (prop.isNotEmpty && value.isNotEmpty) out[prop] = value;
    }
    start = end + 1;
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quote != null) {
      if (ch == quote) quote = null;
    } else if (ch == '"' || ch == "'") {
      quote = ch;
    } else if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
    } else if (ch == ';' && depth == 0) {
      take(i);
    }
  }
  if (start < text.length) take(text.length);
  return out;
}
