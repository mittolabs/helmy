import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';

import 'shots/memory_shot.dart';

void main() {
  testWidgets('what Helmy learned is a page of its own, every lesson on it', (tester) async {
    tester.view.physicalSize = const Size(2880, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AshlarApp(theme: appTheme, darkTheme: appDarkTheme, home: const MemoryShot()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Memory'), findsWidgets);
    expect(find.text('Use the free connection for quick questions.'), findsOneWidget);
    expect(find.text('Delete'), findsNWidgets(12));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
