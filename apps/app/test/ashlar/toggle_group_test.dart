// Tests for Toggle Group. Copied into your app by `ashlar add toggle-group` with the component: they
// check what it promises, so change them as you change it.
import 'dart:ui' show Tristate;

import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/theme.dart';
import 'package:helmy/ui/core/ashlar/toggle.dart';
import 'package:helmy/ui/core/ashlar/toggle_group.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

/// These tests measure how controls look, so without the room a finger's press area
/// takes on a phone (tap_target_test.dart covers that).
Widget app2(Widget child) => AshlarApp(
  theme: AshlarThemeData.light().copyWith(tapTarget: 0),
  home: Center(child: child),
);

void main() {
  group('Toggle', () {
    testWidgets('a chip is a filled pill, the primary colour once chosen', (
      tester,
    ) async {
      await tester.pumpWidget(
        app2(
          ToggleGroup<String>(
            variant: ToggleVariant.chip,
            size: ToggleSize.xl,
            spacing: 8,
            values: const {'all'},
            onChanged: (_) {},
            items: const [
              ToggleGroupItem('all', Text('All')),
              ToggleGroupItem('new', Text('New')),
            ],
          ),
        ),
      );
      final t = AshlarThemeData.light();
      BoxDecoration of(String label) =>
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text(label),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(of('All').color, t.colors.primary);
      expect(of('New').color, t.colors.secondary);
      final height = tester.getSize(find.byType(Toggle).first).height;
      expect(height, t.control(48));
      expect(of('New').borderRadius, BorderRadius.circular(height));
    });

    testWidgets('stays pressed and says so', (tester) async {
      final semantics = tester.ensureSemantics();
      var on = false;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, set) => Toggle(
              pressed: on,
              onChanged: (v) => set(() => on = v),
              semanticLabel: 'Bold',
              child: const Text('B'),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(Toggle));
      await tester.pump();
      expect(on, isTrue);
      final node = tester.getSemantics(find.byType(Toggle)).getSemanticsData();
      expect(node.label, 'Bold');
      expect(node.flagsCollection.isToggled, Tristate.isTrue);
      semantics.dispose();
    });

    testWidgets(
      'a group presses one at a time, or several; the arrows move between them',
      (tester) async {
        var values = <String>{};
        var multiple = false;
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, set) => ToggleGroup<String>(
                values: values,
                multiple: multiple,
                onChanged: (v) => set(() => values = v),
                items: const [
                  ToggleGroupItem('a', Text('A')),
                  ToggleGroupItem('b', Text('B')),
                  ToggleGroupItem('c', Text('C')),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.text('A'));
        await tester.pump();
        await tester.tap(find.text('B'));
        await tester.pump();
        expect(values, {'b'});
        await tester.tap(find.text('B'));
        await tester.pump();
        expect(values, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(values, {'c'});
        multiple = true;
        tester.element(find.byType(StatefulBuilder)).markNeedsBuild();
        await tester.pump();
        await tester.tap(find.text('A'));
        await tester.pump();
        expect(values, {'a', 'c'});
      },
    );
  });

  testWidgets(
    'a spaced toggle group stands its toggles apart, and can stand upright',
    (tester) async {
      await tester.pumpWidget(
        app2(
          ToggleGroup<int>(
            values: const {1},
            spacing: 8,
            axis: Axis.vertical,
            onChanged: (_) {},
            items: const [
              ToggleGroupItem(1, Text('A')),
              ToggleGroupItem(2, Text('B')),
            ],
          ),
        ),
      );
      final a = tester.getRect(find.byType(Toggle).first),
          b = tester.getRect(find.byType(Toggle).last);
      expect(b.top - a.bottom, 8);
      expect(a.left, b.left);
    },
  );
}
