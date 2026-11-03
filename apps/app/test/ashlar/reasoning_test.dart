// Tests for Reasoning. Copied into your app by `ashlar add reasoning` with the component:
// they check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/reasoning.dart';
import 'package:helmy/ui/core/ashlar/shimmer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(
  home: Padding(padding: const EdgeInsets.all(16), child: child),
);

void main() {
  group('Reasoning', () {
    testWidgets('shows its thoughts while thinking, under a shimmering line', (tester) async {
      await tester.pumpWidget(app(const Reasoning(thinking: true, child: Text('Checking stock'))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
      expect(find.text('Checking stock').hitTestable(), findsOneWidget);
    });

    testWidgets('says how long it took and folds away when done', (tester) async {
      await tester.pumpWidget(app(const Reasoning(thinking: true, child: Text('Checking stock'))));
      await tester.pumpWidget(
        app(const Reasoning(took: Duration(seconds: 12), child: Text('Checking stock'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thought for 12 seconds'), findsOneWidget);
      expect(find.byType(Shimmer), findsNothing);
      expect(find.text('Checking stock').hitTestable(), findsNothing);
      await tester.tap(find.text('Thought for 12 seconds'));
      await tester.pumpAndSettle();
      expect(find.text('Checking stock').hitTestable(), findsOneWidget);
    });

    testWidgets('stays open when the person opened it', (tester) async {
      await tester.pumpWidget(app(const Reasoning(thinking: true, child: Text('Checking stock'))));
      // Closed and opened again while thinking: theirs to close now.
      await tester.tap(find.text('Thinking…'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Thinking…'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(
        app(const Reasoning(took: Duration(minutes: 2), child: Text('Checking stock'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thought for 2 minutes'), findsOneWidget);
      expect(find.text('Checking stock').hitTestable(), findsOneWidget);
    });

    testWidgets('tells a screen reader whether it is open', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const Reasoning(took: Duration(seconds: 1), child: Text('x'))));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Thought for 1 second')),
        matchesSemantics(
          label: 'Thought for 1 second',
          isButton: true,
          hasExpandedState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
    });
  });
}
