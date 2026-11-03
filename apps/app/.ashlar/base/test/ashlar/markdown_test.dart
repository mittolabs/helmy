// Tests for Markdown. Copied into your app by `ashlar add markdown` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(
  home: SingleChildScrollView(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

/// Every run of text drawn, joined.
String drawn(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join('\n');

void main() {
  group('parseMarkdown', () {
    test('reads the blocks people and models write', () {
      final blocks = parseMarkdown("""
# Title

A paragraph
on two lines.

- one
- two
  - nested

1. first
2. second

> quoted

| Name | Price |
|:-----|------:|
| Tea  | 120   |

---

```dart
print('hi');
```""");
      expect(blocks.map((b) => b.runtimeType), [
        MdHeading,
        MdParagraph,
        MdList,
        MdList,
        MdQuote,
        MdTable,
        MdRule,
        MdCode,
      ]);
      expect((blocks[1] as MdParagraph).text, 'A paragraph\non two lines.');
      final bullets = blocks[2] as MdList;
      expect(bullets.items, hasLength(2));
      expect(bullets.items[1].children.last, isA<MdList>());
      expect((blocks[3] as MdList).ordered, isTrue);
      final table = blocks[5] as MdTable;
      expect(table.head, ['Name', 'Price']);
      expect(table.rows, [
        ['Tea', '120'],
      ]);
      expect(table.align, [-1, 1]);
      final code = blocks[7] as MdCode;
      expect(code.language, 'dart');
      expect(code.code, "print('hi');");
      expect(code.open, isFalse);
    });

    test('takes a code block still arriving as one, open', () {
      final blocks = parseMarkdown('Here:\n\n```js\nconst a = 1;\nconst b');
      final code = blocks.last as MdCode;
      expect(code.open, isTrue);
      expect(code.code, 'const a = 1;\nconst b');
    });

    test('reads boxes to tick in a list', () {
      final list = parseMarkdown('- [x] done\n- [ ] not yet').single as MdList;
      expect(list.items.map((i) => i.checked), [true, false]);
      expect((list.items.first.children.single as MdParagraph).text, 'done');
    });

    test('keeps an ordered list\'s first number', () {
      final list = parseMarkdown('3. c\n4. d').single as MdList;
      expect(list.start, 3);
    });
  });

  group('parseInline', () {
    test('marks bold, italic, struck, code and links', () {
      final runs = parseInline(
        'a **bold** _it_ ~~gone~~ `x()` [site](https://a.b) https://c.d',
      );
      MdSpan run(String text) => runs.firstWhere((r) => r.text == text);
      expect(run('bold').bold, isTrue);
      expect(run('it').italic, isTrue);
      expect(run('gone').strike, isTrue);
      expect(run('x()').code, isTrue);
      expect(run('site').link, 'https://a.b');
      expect(run('https://c.d').link, 'https://c.d');
    });

    test('takes a mark not yet closed as running to the end', () {
      final runs = parseInline('so **this is still');
      expect(runs.last.text, 'this is still');
      expect(runs.last.bold, isTrue);
      expect(parseInline('a `cod').last.code, isTrue);
    });

    test('leaves an underscore inside a word alone', () {
      expect(parseInline('snake_case_name').single.text, 'snake_case_name');
    });

    test('leaves a lone star alone', () {
      expect(parseInline('2 * 3').map((r) => r.text).join(), '2 * 3');
    });

    test('reads escaped characters as themselves', () {
      expect(parseInline(r'\*not\*').single.text, '*not*');
    });
  });

  group('Markdown', () {
    testWidgets('draws the text without its marks', (tester) async {
      await tester.pumpWidget(
        app(const Markdown('# Hello\n\nSome **bold** and `code`.')),
      );
      final text = drawn(tester);
      expect(text, contains('Hello'));
      expect(text, contains('Some bold and'));
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('`')));
    });

    testWidgets('tells a screen reader which lines are headings', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const Markdown('## Steps\n\nDo this.')));
      expect(
        tester.getSemantics(find.text('Steps')),
        matchesSemantics(label: 'Steps', isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('calls onLink with the address of a tapped link', (
      tester,
    ) async {
      String? opened;
      await tester.pumpWidget(
        app(
          Markdown(
            '[docs](https://ui.ashlar.ke)',
            onLink: (url) => opened = url,
          ),
        ),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(RichText).first) + const Offset(8, 8),
      );
      expect(opened, 'https://ui.ashlar.ke');
    });

    testWidgets('shows a caret only while streaming', (tester) async {
      final caret = find.descendant(
        of: find.byType(Markdown),
        matching: find.byType(FadeTransition),
      );
      await tester.pumpWidget(app(const Markdown('Thinking', streaming: true)));
      expect(caret, findsOneWidget);
      await tester.pumpWidget(app(const Markdown('Thinking')));
      expect(caret, findsNothing);
    });

    testWidgets('draws a code block still arriving, and copies it', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.pumpWidget(
        app(const Markdown('```dart\nvoid main() {}', streaming: true)),
      );
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('void main() {}'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Copy the code'));
      await tester.pump();
      expect(copied, 'void main() {}');
      expect(find.bySemanticsLabel('Copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.bySemanticsLabel('Copy the code'), findsOneWidget);
    });

    testWidgets('draws a table and lists without overflowing a phone', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(360, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          const Markdown("""
| Plan | Seats | Price a month, before tax |
|---|---:|---:|
| Starter | 3 | 1,200 |
| Team | 25 | 9,800 |

- [x] Chosen a plan
- [ ] Paid

1. One
2. Two"""),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(drawn(tester), contains('Starter'));
      expect(drawn(tester), contains('2.'));
    });

    testWidgets('lets codeBuilder draw code blocks', (tester) async {
      await tester.pumpWidget(
        app(
          Markdown(
            '```sh\nls\n```',
            codeBuilder: (context, code, language) => Text('[$language] $code'),
          ),
        ),
      );
      expect(find.text('[sh] ls'), findsOneWidget);
    });
  });
}
