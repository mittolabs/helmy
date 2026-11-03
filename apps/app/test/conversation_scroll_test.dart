import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/ashlar/markdown.dart';
import 'package:helmy/ui/core/ashlar/message_scroller.dart';
import 'package:helmy/ui/core/ashlar/tool_call.dart';

const _md = '''
Some text.

| File | Size |
|---|---|
| a.html | 2.3 KB |

```dart
void main() {}
```

- a bullet
''';

/// Found 2026-11-03: the scroller's jump-to-end button sat over the rows in a
/// Stack, so a wheel or trackpad scroll starting on it never reached the
/// scroller. It shows whenever you have scrolled up: exactly when you scroll.
void main() {
  driftTests();
  testWidgets('scrolls start anywhere over the conversation, the end button too', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AshlarApp(
        theme: appTheme,
        darkTheme: appDarkTheme,
        home: MessageScroller(
          items: [
            for (var i = 0; i < 12; i++) ...[
              MessageScrollerItem(id: 'u$i', anchor: true, child: Text('question $i')),
              MessageScrollerItem(
                id: 't$i',
                child: const ToolCall(name: 'Bash', input: 'ls'),
              ),
              MessageScrollerItem(id: 'm$i', child: const Markdown(_md)),
            ],
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final pad = TestPointer(1, PointerDeviceKind.trackpad);
    final mouse = TestPointer(2, PointerDeviceKind.mouse);
    final stuck = <String>[];
    for (var y = 40.0; y < 800; y += 40) {
      for (final x in [100.0, 600.0]) {
        for (final dir in [1.0, -1.0]) {
          position.jumpTo(position.maxScrollExtent / 2);
          await tester.pumpAndSettle();
          var before = position.pixels;
          await tester.sendEventToBinding(pad.panZoomStart(Offset(x, y)));
          await tester.sendEventToBinding(
            pad.panZoomUpdate(Offset(x, y), pan: Offset(8, dir * 90)),
          );
          await tester.sendEventToBinding(pad.panZoomEnd());
          await tester.pumpAndSettle();
          if (position.pixels == before) stuck.add('trackpad ($x, $y) $dir');
          before = position.pixels;
          await tester.sendEventToBinding(mouse.hover(Offset(x, y)));
          await tester.sendEventToBinding(mouse.scroll(Offset(0, dir * -100)));
          await tester.pumpAndSettle();
          if (position.pixels == before) stuck.add('wheel ($x, $y) $dir');
        }
      }
    }
    expect(stuck, isEmpty);
  });
}

final _wide =
    '```\n${List.filled(12, 'a very long line of output ' * 12).join('\n')}\n```\n\n'
    '| a | b |\n|---|---|\n| ${'x' * 300} | y |\n';

/// Found 2026-11-03: a wheel or momentum scroll always drifts a little sideways,
/// and a wide code block or table took it for its own sideways scroll, so the
/// conversation stopped moving wherever the pointer was over one.
void driftTests() {
  testWidgets('a drifting scroll over wide code or tables moves the conversation', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AshlarApp(
        theme: appTheme,
        darkTheme: appDarkTheme,
        home: MessageScroller(
          items: [for (var i = 0; i < 8; i++) MessageScrollerItem(id: i, child: Markdown(_wide))],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final page = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final stuck = <double>[];
    for (var y = 60.0; y < 680; y += 40) {
      page.jumpTo((page.minScrollExtent + page.maxScrollExtent) / 2);
      await tester.pumpAndSettle();
      final before = page.pixels;
      await tester.sendEventToBinding(mouse.hover(Offset(300, y)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(3, -60)));
      await tester.pumpAndSettle();
      if (page.pixels == before) stuck.add(y);
    }
    expect(stuck, isEmpty);

    // A scroll that is mostly sideways still moves the code.
    final code = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    final codeAt = tester.getCenter(code.first);
    final sideways = tester.state<ScrollableState>(
      find.descendant(of: code.first, matching: find.byType(Scrollable)),
    );
    final pageBefore = page.pixels;
    await tester.sendEventToBinding(mouse.hover(codeAt));
    await tester.sendEventToBinding(mouse.scroll(const Offset(80, 2)));
    await tester.pumpAndSettle();
    expect(sideways.position.pixels, greaterThan(0));
    expect(page.pixels, pageBefore);
  });
}
