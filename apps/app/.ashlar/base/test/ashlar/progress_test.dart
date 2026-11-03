// Tests for Progress. Copied into your app by `ashlar add progress` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/progress.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      themeMode: mode,
      home: Center(child: child),
    );

void main() {
  group('Progress', () {
    testWidgets('fills to its value and reads it as a percentage', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          const SizedBox(
            width: 200,
            child: Progress(value: .4, semanticLabel: 'Upload'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fill = tester.getSize(
        find
            .descendant(
              of: find.byType(Progress),
              matching: find.byType(DecoratedBox),
            )
            .last,
      );
      expect(fill.width, closeTo(80, .5));
      final node = tester
          .getSemantics(find.byType(Progress))
          .getSemanticsData();
      expect(node.label, 'Upload');
      expect(node.value, '40%');
      semantics.dispose();
    });

    testWidgets('unknown, it sweeps; with less motion asked for, it is still', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(const SizedBox(width: 200, child: Progress())),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: app(const SizedBox(width: 200, child: Progress())),
        ),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
