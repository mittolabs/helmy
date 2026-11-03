import 'package:flutter/widgets.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import '../chat/widgets/step_input.dart' show CodeColors;

/// Syntax colors for code in answers, in the same few colors commands use
/// in steps: strings green, keywords and tags blue, numbers and attributes
/// amber, comments quiet. Read with highlight.js's rules (re_highlight).
class CodeHighlighter {
  CodeHighlighter._();

  static final _highlight = Highlight()..registerLanguages(builtinAllLanguages);

  /// What a block that names no language is tried as, most likely first.
  static const _guesses = [
    'dart',
    'typescript',
    'javascript',
    'python',
    'bash',
    'json',
    'yaml',
    'xml',
    'css',
    'sql',
    'go',
    'swift',
    'kotlin',
    'java',
    'rust',
    'php',
    'ruby',
    'markdown',
  ];

  /// Longer than this, code is left plain: coloring it would cost more than
  /// it gives while it streams.
  static const _maxChars = 40000;

  static final Map<(String, String?, int), TextSpan?> _cache = {};

  /// [code] as colored spans in [base], for the theme [c]; null when it
  /// cannot be read, so it is drawn plain.
  static TextSpan? spans(String code, String? language, TextStyle base, CodeColors c) {
    if (code.length > _maxChars || code.trim().isEmpty) return null;
    final key = (code, language, c.plain.toARGB32());
    if (_cache.containsKey(key)) return _cache[key];
    TextSpan? out;
    try {
      final lang = language?.trim().toLowerCase();
      final HighlightResult result = lang != null && lang.isNotEmpty && _known(lang)
          ? _highlight.highlight(code: code, language: lang)
          : _highlight.highlightAuto(code, _guesses);
      final renderer = TextSpanRenderer(base, _theme(c));
      result.render(renderer);
      out = renderer.span;
    } on Object {
      out = null;
    }
    if (_cache.length > 200) _cache.remove(_cache.keys.first);
    return _cache[key] = out;
  }

  /// A language highlight.js knows, by name or alias ("html", "sh").
  static bool _known(String lang) => _highlight.getLanguage(lang) != null;

  static Map<String, TextStyle> _theme(CodeColors c) {
    final keyword = TextStyle(color: c.flag);
    final string = TextStyle(color: c.string);
    final number = TextStyle(color: c.number);
    final quiet = TextStyle(color: c.quiet, fontStyle: FontStyle.italic);
    final title = TextStyle(color: c.plain, fontWeight: FontWeight.w600);
    return {
      'keyword': keyword,
      'built_in': keyword,
      'type': keyword,
      'literal': keyword,
      'selector-tag': keyword,
      'tag': keyword,
      'name': keyword,
      'section': title,
      'title': title,
      'title.function': title,
      'title.class': title,
      'string': string,
      'regexp': string,
      'symbol': string,
      'char': string,
      'template-tag': string,
      'link': string,
      'number': number,
      'attr': number,
      'attribute': number,
      'variable': number,
      'meta': quiet,
      'comment': quiet,
      'quote': quiet,
      'doctag': quiet,
      'deletion': TextStyle(color: c.quiet, decoration: TextDecoration.lineThrough),
      'addition': string,
    };
  }
}
