// Tests for Dialog. Copied into your app by `ashlar add dialog` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/dialog.dart';
import 'package:helmy/ui/core/ashlar/input.dart';
import 'package:helmy/ui/core/ashlar/theme.dart';
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
          child: Button(
            onPressed: () => show(context),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('Dialog', () {
    Future<List<Object?>> open(WidgetTester tester) async {
      final results = <Object?>[];
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Button(
              onPressed: () async => results.add(
                await showAshlarDialog<String>(
                  context: context,
                  builder: (context) => Dialog(
                    title: const Text('Delete?'),
                    description: const Text('This cannot be undone.'),
                    actions: [
                      Button(
                        onPressed: () => Navigator.pop(context, 'delete'),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsOneWidget);
      return results;
    }

    testWidgets('an action closes it with its value', (tester) async {
      final results = await open(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsNothing);
      expect(results, ['delete']);
    });

    testWidgets('Escape closes it', (tester) async {
      final results = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsNothing);
      expect(results, [null]);
    });

    testWidgets('the close button and a tap outside close it', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('Close').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsNothing);
    });

    testWidgets('it carries the dark theme', (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Button(
              onPressed: () => showAshlarDialog(
                context: context,
                builder: (_) => const Dialog(title: Text('Hi')),
              ),
              child: const Text('Open'),
            ),
          ),
          mode: AshlarThemeMode.dark,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final panel = tester.widget<Container>(
        find
            .ancestor(of: find.text('Hi'), matching: find.byType(Container))
            .first,
      );
      expect(
        (panel.decoration! as BoxDecoration).color,
        AshlarColors.dark.background,
      );
    });
  });

  testWidgets('a dialog with a field sits above the keyboard', (tester) async {
    await open(
      tester,
      (context) => showAshlarDialog<void>(
        context: context,
        builder: (_) => const Dialog(
          title: Text('Rename'),
          content: Input(placeholder: 'Name'),
        ),
      ),
    );
    expect(tester.getRect(find.byType(Dialog)).bottom, lessThanOrEqualTo(500));
    expect(tester.getRect(find.byType(Input)).bottom, lessThanOrEqualTo(500));
  });
}
