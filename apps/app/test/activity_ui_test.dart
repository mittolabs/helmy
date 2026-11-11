import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/core/ashlar/app.dart';

import 'activity_shot.dart';

void main() {
  testWidgets('one concrete summary expands to purposes, then technical details', (tester) async {
    await tester.pumpWidget(const AshlarApp(home: ActivityShot(work: true)));
    await tester.pumpAndSettle();
    expect(find.text('Added line numbers and tested editing'), findsOneWidget);
    expect(find.text('Added the line-number gutter'), findsNothing);
    await tester.tap(find.text('Added line numbers and tested editing'));
    await tester.pumpAndSettle();
    expect(find.text('Added the line-number gutter'), findsOneWidget);
    expect(find.text('Tested editing and saving'), findsOneWidget);
    expect(find.textContaining('class LineNumberGutter', findRichText: true), findsNothing);
    await tester.tap(find.text('Added the line-number gutter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('class LineNumberGutter', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approval shows its purpose and keeps the script behind technical details', (
    tester,
  ) async {
    await tester.pumpWidget(const AshlarApp(home: ActivityShot()));
    await tester.pumpAndSettle();
    expect(find.text('Prepare Helmy to reopen?'), findsOneWidget);
    expect(find.text('Prepare restart'), findsOneWidget);
    expect(find.textContaining('subprocess.Popen'), findsNothing);
    expect(find.textContaining('Wants to run a command'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('subprocess.Popen', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
