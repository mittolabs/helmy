// Tests for Tooltip. Copied into your app by `ashlar add tooltip` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/tooltip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      themeMode: mode,
      home: Center(child: child),
    );

void main() {
  group('Tooltip', () {
    Widget tip() => Tooltip(
      message: 'Add to library',
      child: Button(
        semanticLabel: 'Add',
        onPressed: () {},
        child: const Text('+'),
      ),
    );

    testWidgets('shows on hover', (tester) async {
      await tester.pumpWidget(app(tip()));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('+')));
      await tester.pumpAndSettle();
      expect(find.text('Add to library'), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Add to library'), findsNothing);
    });

    testWidgets('shows on keyboard focus', (tester) async {
      await tester.pumpWidget(app(tip()));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('Add to library'), findsOneWidget);
    });

    testWidgets('a screen reader hears the message', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(tip()));
      final node = tester.getSemantics(find.text('+')).getSemanticsData();
      expect(node.label, 'Add');
      expect(node.tooltip, 'Add to library');
      expect(node.flagsCollection.isButton, isTrue);
      semantics.dispose();
    });
  });
}
