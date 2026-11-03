// Tests for Scroll Area. Copied into your app by `ashlar add scroll-area` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/scroll_area.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(at);
  return mouse;
}

void main() {
  testWidgets('a scroll area scrolls and shows its bar under the pointer', (tester) async {
    await tester.pumpWidget(
      app(
        SizedBox(
          height: 200,
          width: 200,
          child: ScrollArea(child: Column(children: [for (var i = 0; i < 40; i++) Text('Tag $i')])),
        ),
      ),
    );
    expect(tester.widget<RawScrollbar>(find.byType(RawScrollbar)).thumbVisibility, isFalse);
    await mouseAt(tester, tester.getCenter(find.byType(ScrollArea)));
    await tester.pump();
    expect(tester.widget<RawScrollbar>(find.byType(RawScrollbar)).thumbVisibility, isTrue);
    await tester.drag(find.byType(ScrollArea), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Tag 0').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
