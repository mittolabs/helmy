// Tests for AshlarApp. Copied into your app with the component: they check what it
// promises, so change them as you change it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/theme.dart';

/// A router with one page, which shows the theme it is given.
class _Delegate extends RouterDelegate<Object> with ChangeNotifier {
  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) =>
        Text(AshlarTheme.of(context).brightness == Brightness.dark ? 'dark' : 'light'),
  );

  @override
  Future<bool> popRoute() async => false;

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

void main() {
  testWidgets('a home page gets the theme', (tester) async {
    await tester.pumpWidget(
      AshlarApp(
        themeMode: AshlarThemeMode.light,
        home: Builder(
          builder: (context) =>
              Text(AshlarTheme.of(context).brightness == Brightness.dark ? 'dark' : 'light'),
        ),
      ),
    );
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('a router\'s pages get the theme, and follow the theme mode', (tester) async {
    final config = RouterConfig<Object>(routerDelegate: _Delegate());
    await tester.pumpWidget(
      AshlarApp.router(routerConfig: config, themeMode: AshlarThemeMode.light),
    );
    expect(find.text('light'), findsOneWidget);
    await tester.pumpWidget(
      AshlarApp.router(routerConfig: config, themeMode: AshlarThemeMode.dark),
    );
    expect(find.text('dark'), findsOneWidget);
  });
}
