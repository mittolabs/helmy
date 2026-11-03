import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/chat/widgets/step_input.dart';
import 'package:helmy/ui/core/code_highlight.dart';

const _c = CodeColors(
  plain: Color(0xFF111111),
  quiet: Color(0xFF777777),
  string: Color(0xFF1F7A45),
  flag: Color(0xFF2357B5),
  number: Color(0xFFA35A00),
);
const _base = TextStyle(fontSize: 13, color: Color(0xFF111111));

/// Each piece of text with the color it is drawn in.
Map<String, Color?> _colors(TextSpan span) {
  final out = <String, Color?>{};
  void walk(InlineSpan s, Color? inherited) {
    if (s is! TextSpan) return;
    final color = s.style?.color ?? inherited;
    if (s.text != null && s.text!.trim().isNotEmpty) out[s.text!.trim()] = color;
    for (final child in s.children ?? const <InlineSpan>[]) {
      walk(child, color);
    }
  }

  walk(span, _base.color);
  return out;
}

void main() {
  test('HTML, named by an alias, gets its tags, attributes and strings colored', () {
    final span = CodeHighlighter.spans(
      '<!-- Header -->\n<h1 class="text-3xl">Listings</h1>',
      'html',
      _base,
      _c,
    )!;
    final colors = _colors(span);
    expect(colors['h1'], _c.flag);
    expect(colors['class'], _c.number);
    expect(colors['"text-3xl"'], _c.string);
    expect(colors['<!-- Header -->'], _c.quiet);
    expect(colors['Listings'], _c.plain);
  });

  test('a named language, and one guessed when the block names none', () {
    final dart = _colors(CodeHighlighter.spans("final name = 'Helmy'; // hi", 'dart', _base, _c)!);
    expect(dart['final'], _c.flag);
    expect(dart["'Helmy'"], _c.string);
    expect(dart['// hi'], _c.quiet);

    final guessed = CodeHighlighter.spans('def greet():\n    return "hello"', null, _base, _c);
    expect(_colors(guessed!)['"hello"'], _c.string);
  });

  test('code too long to color while it streams is left plain', () {
    expect(CodeHighlighter.spans('x' * 50000, 'dart', _base, _c), isNull);
    expect(CodeHighlighter.spans('   ', 'dart', _base, _c), isNull);
  });
}
