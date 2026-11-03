// Tests for Collapsible. Copied into your app by `ashlar add collapsible` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/collapsible.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  testWidgets(
    'a collapsible hides its content from sight, focus and screen readers until opened',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 300,
            child: Collapsible(
              builder: (context, open, toggle) => Button(
                onPressed: toggle,
                child: Text(open ? 'Hide' : 'Show'),
              ),
              child: Button(onPressed: () {}, child: const Text('Inside')),
            ),
          ),
        ),
      );
      expect(find.text('Inside').hitTestable(), findsNothing);
      expect(find.bySemanticsLabel('Inside'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<Collapsible>(),
        isNotNull,
      );
      expect(find.text('Show'), findsOneWidget);
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(find.text('Inside').hitTestable(), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
      semantics.dispose();
    },
  );
}
