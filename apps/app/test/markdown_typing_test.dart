import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/core/markdown_typing.dart';

/// Markdown in the message box, shown as it is typed, the text unchanged.
void main() {
  testWidgets('bold, italic, code and links styled; the marks kept', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    );
    final c = MarkdownTypingController(
      text: 'Make **this** *red* with `x` and [docs](https://a.b)',
    );
    final span = c.buildTextSpan(context: ctx, withComposing: false);
    final flat = <TextSpan>[];
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        if (s.text != null) flat.add(s);
        s.children?.forEach(walk);
      }
    }

    walk(span);
    TextStyle? styleOf(String t) => flat.firstWhere((s) => s.text == t).style;
    expect(span.toPlainText(), c.text, reason: 'what is sent is what was typed');
    expect(styleOf('this')?.fontWeight, FontWeight.w700);
    expect(styleOf('red')?.fontStyle, FontStyle.italic);
    expect(styleOf('x')?.fontFamily, 'monospace');
    expect(styleOf('docs')?.decoration, TextDecoration.underline);
    c.enabled = false;
    final plain = c.buildTextSpan(context: ctx, withComposing: false);
    expect(plain.children, isNull);
  });
}
