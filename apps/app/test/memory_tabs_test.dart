import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';

import 'shots/memory_shot.dart';

void main() {
  testWidgets('memory: lessons and files on tabs, each filling the page', (tester) async {
    tester.view.physicalSize = const Size(2880, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AshlarApp(theme: appTheme, darkTheme: appDarkTheme, home: const MemoryShot()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Learned (12)'), findsOneWidget);
    expect(find.text('Use the free connection for quick questions.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Files'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Use the free connection for quick questions.'), findsNothing);
    expect(find.textContaining('No memory yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Lets the screen's own short timers (a toast, a hover) run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
