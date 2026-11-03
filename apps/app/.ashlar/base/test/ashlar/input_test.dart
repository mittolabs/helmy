// Tests for Input. Copied into your app by `ashlar add input` with the component: they
// check what it promises, so change them as you change it.
import 'dart:ui' show Tristate;

import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/input.dart';
import 'package:helmy/ui/core/ashlar/theme.dart';
import 'package:flutter/semantics.dart';
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

void main() {
  group('Input', () {
    testWidgets(
      'typing fills it, hides the placeholder and reports each change',
      (tester) async {
        final seen = <String>[];
        await tester.pumpWidget(
          app(
            SizedBox(
              width: 300,
              child: Input(placeholder: 'Email', onChanged: seen.add),
            ),
          ),
        );
        expect(find.text('Email'), findsOneWidget);
        await tester.tap(find.byType(Input));
        await tester.enterText(find.byType(EditableText), 'a@example.com');
        await tester.pump();
        expect(find.text('Email'), findsNothing);
        expect(seen.last, 'a@example.com');
      },
    );

    testWidgets('focus draws the ring; an error draws it red', (tester) async {
      await tester.pumpWidget(
        app(
          const SizedBox(
            width: 300,
            child: Column(
              children: [
                Input(placeholder: 'A'),
                Input(placeholder: 'B', error: true),
              ],
            ),
          ),
        ),
      );
      final first = find.byType(Input).first, second = find.byType(Input).last;
      expect(
        box(tester, first).boxShadow!.any((s) => s.spreadRadius == 3),
        isFalse,
      );
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(
        box(tester, first).boxShadow!.any((s) => s.spreadRadius == 3),
        isTrue,
      );
      expect(
        (box(tester, second).border! as Border).top.color,
        AshlarColors.light.destructive,
      );
    });

    testWidgets('a screen reader hears a text field named by its placeholder', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(const SizedBox(width: 300, child: Input(placeholder: 'Email'))),
      );
      final node = tester.getSemantics(find.byType(EditableText));
      expect(node.label, 'Email');
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.flagsCollection.isFocused != Tristate.none, isTrue);
      semantics.dispose();
    });

    testWidgets('disabled, it does not take focus', (tester) async {
      final focus = FocusNode();
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 300,
            child: Input(
              placeholder: 'Email',
              enabled: false,
              focusNode: focus,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(Input));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'x');
      expect(find.text('x'), findsNothing);
      focus.dispose();
    });
  });

  testWidgets('a screen reader opens it by tapping it, unless it is disabled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      AshlarApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: Input(placeholder: 'Email', focusNode: focus),
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(EditableText));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(
      const AshlarApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: Input(placeholder: 'Email', enabled: false),
          ),
        ),
      ),
    );
    expect(
      tester
          .getSemantics(find.byType(EditableText))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('each size is as tall as the button of the same name', (
    tester,
  ) async {
    final t = AshlarThemeData.light();
    for (final (size, height) in [
      (InputSize.sm, 32.0),
      (InputSize.md, 36.0),
      (InputSize.lg, 40.0),
      (InputSize.xl, 48.0),
    ]) {
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 300,
            child: Input(size: size, placeholder: 'Name'),
          ),
        ),
      );
      // A new size animates there from the last.
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Input)).height, t.control(height));
    }
  });

  testWidgets(
    'round and raised make a search field: a pill on the card colour',
    (tester) async {
      await tester.pumpWidget(
        app(
          const SizedBox(
            width: 300,
            child: Input(round: true, raised: true, placeholder: 'Search'),
          ),
        ),
      );
      final box =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byType(Input),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      final t = AshlarThemeData.light();
      expect(box.color, t.colors.card);
      expect(box.borderRadius, BorderRadius.circular(999));
      expect((box.border! as Border).top.color, t.colors.card);
    },
  );
}
