// Tests for Textarea. Copied into your app by `ashlar add textarea` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/textarea.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      themeMode: mode,
      home: Center(child: child),
    );

Widget app2(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  testWidgets('a textarea starts three lines tall and grows with its text', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const SizedBox(width: 300, child: Textarea(placeholder: 'Note'))),
    );
    final start = tester.getSize(find.byType(Textarea)).height;
    await tester.enterText(
      find.byType(EditableText),
      List.filled(6, 'line').join('\n'),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(Textarea)).height, greaterThan(start));
    await tester.enterText(
      find.byType(EditableText),
      List.filled(20, 'line').join('\n'),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('Textarea', () {
    Finder grip() => find
        .descendant(
          of: find.byType(Textarea),
          matching: find.byType(CustomPaint),
        )
        .last;

    testWidgets(
      'the grip drags it taller a line at a time, and no shorter than two lines',
      (tester) async {
        await tester.pumpWidget(
          app2(
            const SizedBox(width: 320, child: Textarea(placeholder: 'Note')),
          ),
        );
        final start = tester.getSize(find.byType(Textarea)).height;
        await tester.drag(grip(), const Offset(0, 60));
        await tester.pump();
        expect(
          tester.getSize(find.byType(Textarea)).height,
          closeTo(start + 60, 1),
        );
        await tester.drag(grip(), const Offset(0, -400));
        await tester.pump();
        expect(tester.getSize(find.byType(Textarea)).height, 64);
        await tester.enterText(
          find.byType(EditableText),
          List.filled(10, 'line').join('\n'),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(Textarea)).height, 64);
      },
    );

    testWidgets('without resizable there is no grip', (tester) async {
      await tester.pumpWidget(
        app2(const SizedBox(width: 320, child: Textarea(resizable: false))),
      );
      expect(
        find
            .descendant(
              of: find.byType(Textarea),
              matching: find.byType(MouseRegion),
            )
            .evaluate()
            .where(
              (e) =>
                  (e.widget as MouseRegion).cursor ==
                  SystemMouseCursors.resizeUpDown,
            ),
        isEmpty,
      );
    });
  });
}
