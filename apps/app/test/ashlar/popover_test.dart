// Tests for Popover. Copied into your app by `ashlar add popover` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/input.dart';
import 'package:helmy/ui/core/ashlar/popover.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) => AshlarApp(
  themeMode: mode,
  home: Center(child: child),
);

/// The drawn panel of an open popover, menu or select (PopoverPanel itself fills the screen to place it).
Finder panel() =>
    find.descendant(of: find.byType(PopoverPanel), matching: find.byType(TapRegion)).first;

Widget app2(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  group('Popover', () {
    testWidgets('opens, takes focus, and Escape closes it', (tester) async {
      await tester.pumpWidget(
        app(
          Popover(
            builder: (context, menu) =>
                Button(onPressed: menu.open, child: const Text('Dimensions')),
            content: (context) => const SizedBox(width: 200, child: Input(placeholder: 'Width')),
          ),
        ),
      );
      await tester.tap(find.text('Dimensions'));
      await tester.pumpAndSettle();
      expect(find.text('Width'), findsOneWidget);
      await tester.tap(find.byType(Input));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Width'), findsNothing);
    });

    testWidgets('scrolls when its content is taller than the room', (tester) async {
      await tester.pumpWidget(
        AshlarApp(
          home: Center(
            child: Popover(
              builder: (context, menu) => Button(onPressed: menu.open, child: const Text('Open')),
              content: (context) => const SizedBox(height: 2000, child: Text('Tall')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(panel()).bottom, lessThanOrEqualTo(600));
    });

    testWidgets('flips above when there is no room below', (tester) async {
      await tester.pumpWidget(
        AshlarApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: Popover(
              builder: (context, menu) => Button(onPressed: menu.open, child: const Text('Open')),
              content: (context) => const SizedBox(height: 200, child: Text('Panel')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(panel()).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(Button)).top),
      );
    });
  });

  testWidgets('a popover header', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app2(const PopoverHeader(title: Text('Dimensions'), description: Text('Set the size.'))),
    );
    expect(
      tester.getSemantics(find.text('Dimensions')).getSemanticsData().flagsCollection.isHeader,
      isTrue,
    );
    semantics.dispose();
  });
}
