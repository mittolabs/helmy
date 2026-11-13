// Tests for Tabs. Copied into your app by `ashlar add tabs` with the component: they
// check what it promises, so change them as you change it.
import 'dart:ui' show SemanticsRole, Tristate;

import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/tabs.dart';
import 'package:helmy/ui/core/ashlar/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      themeMode: mode,
      home: Center(child: child),
    );

/// These tests measure how controls look, so without the room a finger's press area
/// takes on a phone (tap_target_test.dart covers that).
Widget app2(Widget child) => AshlarApp(
  theme: AshlarThemeData.light().copyWith(tapTarget: 0),
  home: Center(child: child),
);

void main() {
  group('Tabs', () {
    final tabs = [
      const TabItem(label: Text('Account'), content: Text('Account form')),
      const TabItem(label: Text('Password'), content: Text('Password form')),
      const TabItem(
        label: Text('Billing'),
        content: Text('Billing form'),
        enabled: false,
      ),
      const TabItem(label: Text('Team'), content: Text('Team form')),
    ];

    testWidgets('a tap shows its panel', (tester) async {
      await tester.pumpWidget(app(Tabs(tabs: tabs)));
      expect(find.text('Account form'), findsOneWidget);
      await tester.tap(find.text('Password'));
      await tester.pump();
      expect(find.text('Password form'), findsOneWidget);
      expect(find.text('Account form'), findsNothing);
    });

    testWidgets(
      'the arrow keys move along, skipping a disabled tab and wrapping',
      (tester) async {
        final seen = <int>[];
        await tester.pumpWidget(app(Tabs(tabs: tabs, onChanged: seen.add)));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
        }
        expect(seen, [1, 3, 0]);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(find.text('Team form'), findsOneWidget);
      },
    );

    testWidgets('Tab reaches only the chosen tab, then leaves the row', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tabs(tabs: tabs, initialIndex: 1),
              Button(onPressed: () {}, child: const Text('After')),
            ],
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find
                .ancestor(
                  of: find.byElementPredicate((e) => e == focused),
                  matching: find.byType(Button),
                )
                .evaluate()
                .isNotEmpty ||
            focused.findAncestorWidgetOfExactType<Button>() != null,
        isTrue,
      );
    });

    testWidgets('a screen reader hears tabs, and which is selected', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(Tabs(tabs: tabs)));
      final node = tester.getSemantics(find.text('Account'));
      expect(node.role, SemanticsRole.tab);
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(
        tester.getSemantics(find.text('Password')).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      semantics.dispose();
    });
  });

  group('Tabs', () {
    const tabs = [
      TabItem(label: Text('One'), content: Text('First')),
      TabItem(label: Text('Two'), content: Text('Second')),
    ];

    testWidgets('the line variant underlines the chosen tab', (tester) async {
      await tester.pumpWidget(
        app2(const Tabs(variant: TabsVariant.line, tabs: tabs)),
      );
      BoxDecoration deco(String label) =>
          tester
                  .widget<AnimatedContainer>(
                    find
                        .ancestor(
                          of: find.text(label),
                          matching: find.byType(AnimatedContainer),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect((deco('One').border! as Border).bottom.width, 2);
      // The others have no underline to see.
      expect((deco('Two').border! as Border).bottom.color.a, 0);
    });

    testWidgets(
      'vertical tabs sit beside the panel and move with the up and down arrows',
      (tester) async {
        await tester.pumpWidget(
          app2(
            const SizedBox(
              width: 400,
              child: Tabs(axis: Axis.vertical, tabs: tabs),
            ),
          ),
        );
        expect(
          tester.getTopLeft(find.text('Two')).dy,
          greaterThan(tester.getTopLeft(find.text('One')).dy),
        );
        expect(
          tester.getTopLeft(find.text('First')).dx,
          greaterThan(tester.getTopRight(find.text('One')).dx),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(find.text('Second'), findsOneWidget);
      },
    );
  });
}
