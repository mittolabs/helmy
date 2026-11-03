// Tests for Empty. Copied into your app by `ashlar add empty` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/empty.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) => AshlarApp(
  themeMode: mode,
  home: Center(child: child),
);

Widget app2(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  testWidgets('empty lays out in light and dark, with its actions', (tester) async {
    for (final mode in AshlarThemeMode.values) {
      await tester.pumpWidget(
        app(
          const SizedBox(
            width: 400,
            child: Empty(
              title: Text('No projects'),
              description: Text('Create one.'),
              actions: [Text('Create')],
            ),
          ),
          mode: mode,
        ),
      );
      expect(find.text('Create'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('empty states on a muted ground and in a border', (tester) async {
    await tester.pumpWidget(
      app2(
        const SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Empty(background: true, title: Text('A')),
              Empty(border: true, title: Text('B')),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(Empty).first).width, 500);
    expect(tester.takeException(), isNull);
  });
}
