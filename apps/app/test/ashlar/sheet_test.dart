// Tests for Sheet. Copied into your app by `ashlar add sheet` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/input.dart';
import 'package:helmy/ui/core/ashlar/sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

Future<void> open(WidgetTester tester, void Function(BuildContext) show) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  // A keyboard 300 tall.
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AshlarApp(
      home: Builder(
        builder: (context) => Center(
          child: Button(onPressed: () => show(context), child: const Text('Open')),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('Sheet', () {
    Future<void> open(WidgetTester tester, SheetSide side) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Button(
              onPressed: () => showSheet(
                context: context,
                side: side,
                builder: (context) =>
                    const Sheet(title: Text('Edit profile'), content: Text('Form')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('slides in at the right edge, no wider than 384', (tester) async {
      await open(tester, SheetSide.right);
      final panel = tester.getRect(
        find.ancestor(of: find.text('Edit profile'), matching: find.byType(SafeArea)).first,
      );
      expect(panel.right, 800);
      expect(panel.width, lessThanOrEqualTo(384));
      expect(panel.height, 600);
    });

    testWidgets('at the left edge, and from the bottom at its own height', (tester) async {
      await open(tester, SheetSide.left);
      expect(
        tester
            .getRect(
              find.ancestor(of: find.text('Edit profile'), matching: find.byType(SafeArea)).first,
            )
            .left,
        0,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await open(tester, SheetSide.bottom);
      final panel = tester.getRect(
        find.ancestor(of: find.text('Edit profile'), matching: find.byType(SafeArea)).first,
      );
      expect(panel.bottom, 600);
      expect(panel.height, lessThan(300));
    });

    testWidgets('the close button, Escape and a tap outside close it', (tester) async {
      await open(tester, SheetSide.right);
      await tester.tap(find.bySemanticsLabel('Close').last);
      await tester.pumpAndSettle();
      expect(find.text('Edit profile'), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Edit profile'), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 300));
      await tester.pumpAndSettle();
      expect(find.text('Edit profile'), findsNothing);
    });
  });

  testWidgets('a sheet from the bottom rises above the keyboard', (tester) async {
    await open(
      tester,
      (context) => showSheet<void>(
        context: context,
        side: SheetSide.bottom,
        builder: (_) => const Sheet(
          title: Text('Search'),
          content: Input(placeholder: 'Search'),
        ),
      ),
    );
    expect(tester.getRect(find.byType(Input)).bottom, lessThanOrEqualTo(500));
  });

  testWidgets('a sheet without its close button', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Button(
            onPressed: () => showSheet(
              context: context,
              builder: (_) => const Sheet(title: Text('Edit'), showClose: false),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.descendant(of: find.byType(Sheet), matching: find.byType(Button)), findsNothing);
    semantics.dispose();
  });
}
