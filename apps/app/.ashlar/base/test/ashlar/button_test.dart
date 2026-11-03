// Tests for Button. Copied into your app by `ashlar add button` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests measure how controls look, so without the room a finger's press area
/// takes on a phone (tap_target_test.dart covers that).
Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      theme: AshlarThemeData.light().copyWith(tapTarget: 0),
      darkTheme: AshlarThemeData.dark().copyWith(tapTarget: 0),
      themeMode: mode,
      home: Center(child: child),
    );

/// The decoration of the first box a control draws.
BoxDecoration box(WidgetTester tester, Finder of) =>
    tester
            .widget<AnimatedContainer>(
              find
                  .descendant(of: of, matching: find.byType(AnimatedContainer))
                  .first,
            )
            .decoration!
        as BoxDecoration;

/// These tests measure how controls look, so without the room a finger's press area
/// takes on a phone (tap_target_test.dart covers that).
Widget app2(Widget child) => AshlarApp(
  theme: AshlarThemeData.light().copyWith(tapTarget: 0),
  home: Center(child: child),
);

void main() {
  group('Button', () {
    testWidgets('a tap, Enter and Space all press it', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        app(Button(onPressed: () => presses++, child: const Text('Save'))),
      );
      await tester.tap(find.text('Save'));
      expect(presses, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(presses, 3);
    });

    testWidgets('disabled, it ignores taps and is announced as disabled', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(const Button(onPressed: null, child: Text('Save'))),
      );
      await tester.tap(find.text('Save'), warnIfMissed: false);
      expect(
        tester.getSemantics(find.text('Save')),
        matchesSemantics(
          label: 'Save',
          isButton: true,
          hasEnabledState: true,
          isFocusable: false,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a screen reader hears its text as a button', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(Button(onPressed: () {}, child: const Text('Save'))),
      );
      expect(
        tester.getSemantics(find.text('Save')),
        matchesSemantics(
          label: 'Save',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the focus ring shows for keyboard focus, not for a tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(Button(onPressed: () {}, child: const Text('Save'))),
      );
      final button = find.byType(Button);
      bool ring() =>
          box(tester, button).boxShadow!.any((s) => s.spreadRadius == 3);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(ring(), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(ring(), isTrue);
    });

    testWidgets('hovering changes its fill', (tester) async {
      await tester.pumpWidget(
        app(
          Button(
            variant: ButtonVariant.outline,
            onPressed: () {},
            child: const Text('Save'),
          ),
        ),
      );
      final before = box(tester, find.byType(Button)).color;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Save')));
      await tester.pumpAndSettle();
      expect(box(tester, find.byType(Button)).color, isNot(before));
      expect(box(tester, find.byType(Button)).color, AshlarColors.light.accent);
    });

    testWidgets('every variant and size lays out without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          Wrap(
            children: [
              for (final v in ButtonVariant.values)
                for (final s in ButtonSize.values)
                  Button(
                    variant: v,
                    size: s,
                    onPressed: () {},
                    semanticLabel: 'x',
                    child: const Text('Go'),
                  ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final heights = [
        for (final e in find.byType(Button).evaluate()) e.size!.height,
      ];
      expect(heights.take(4), [32, 36, 40, 36]);
    });
  });

  testWidgets(
    'button sizes, and an invalid button draws a destructive border',
    (tester) async {
      await tester.pumpWidget(
        app2(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in [
                ButtonSize.xs,
                ButtonSize.iconXs,
                ButtonSize.iconSm,
                ButtonSize.iconLg,
              ])
                Button(
                  size: s,
                  semanticLabel: '$s',
                  onPressed: () {},
                  child: const Text('A'),
                ),
              Button(
                variant: ButtonVariant.outline,
                error: true,
                onPressed: () {},
                child: const Text('Bad'),
              ),
            ],
          ),
        ),
      );
      final sizes = [
        for (final e in find.byType(Button).evaluate().take(4)) e.size!,
      ];
      expect(sizes.map((s) => s.height), [24, 24, 32, 40]);
      expect(sizes.skip(1).map((s) => s.width), [24, 32, 40]);
      final bad = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(Button).last,
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        ((bad.decoration! as BoxDecoration).border! as Border).top.color,
        AshlarColors.light.destructive,
      );
    },
  );

  testWidgets('xl is 48 tall, its icon square 48, with the larger corners', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Button(
              key: const Key('xl'),
              size: ButtonSize.xl,
              onPressed: () {},
              child: const Text('Book'),
            ),
            Button(
              key: const Key('icon'),
              size: ButtonSize.iconXl,
              semanticLabel: 'Add',
              onPressed: () {},
              child: const Text('+'),
            ),
          ],
        ),
      ),
    );
    final t = AshlarThemeData.light();
    expect(tester.getSize(find.byKey(const Key('xl'))).height, t.control(48));
    expect(tester.getSize(find.byKey(const Key('icon'))), Size.square(t.control(48)));
    expect(
      box(tester, find.byKey(const Key('xl'))).borderRadius,
      BorderRadius.circular(t.radiusLg),
    );
  });

  testWidgets('icon2xl is a 64 square with a larger icon', (tester) async {
    await tester.pumpWidget(
      app(
        Button(
          key: const Key('play'),
          size: ButtonSize.icon2xl,
          round: true,
          semanticLabel: 'Play',
          onPressed: () {},
          child: const Icon(IconData(0x41)),
        ),
      ),
    );
    final t = AshlarThemeData.light();
    expect(
      tester.getSize(find.byKey(const Key('play'))),
      Size.square(t.control(64)),
    );
    expect(IconTheme.of(tester.element(find.byType(Icon))).size, 28);
  });

  testWidgets('round makes a pill, or a circle of an icon button', (tester) async {
    await tester.pumpWidget(
      app(
        Button(
          key: const Key('b'),
          size: ButtonSize.iconLg,
          round: true,
          semanticLabel: 'Back',
          onPressed: () {},
          child: const Text('<'),
        ),
      ),
    );
    final height = tester.getSize(find.byKey(const Key('b'))).height;
    expect(
      box(tester, find.byKey(const Key('b'))).borderRadius,
      BorderRadius.circular(height),
    );
  });

  testWidgets('a badge sits over the top end corner', (tester) async {
    await tester.pumpWidget(
      app(
        Button(
          key: const Key('b'),
          size: ButtonSize.iconLg,
          semanticLabel: 'Notifications',
          badge: const SizedBox(key: Key('dot'), width: 8, height: 8),
          onPressed: () {},
          child: const Text('!'),
        ),
      ),
    );
    final button = tester.getRect(find.byKey(const Key('b')));
    final dot = tester.getRect(find.byKey(const Key('dot')));
    expect(dot.topRight, button.topRight);
  });
}
