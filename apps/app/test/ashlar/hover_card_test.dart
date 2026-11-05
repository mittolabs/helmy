// Tests for Hover Card. Copied into your app by `ashlar add hover-card` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/hover_card.dart';
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
  testWidgets('a hover card waits, appears, stays while the pointer is on it, then goes', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        HoverCard(
          content: (context) => const Text('Profile card'),
          child: Button(variant: ButtonVariant.link, onPressed: () {}, child: const Text('@maya')),
        ),
      ),
    );
    final mouse = await mouseAt(tester, tester.getCenter(find.text('@maya')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Profile card'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Profile card'), findsOneWidget);
    // Across the gap and onto the card: it stays.
    await mouse.moveTo(tester.getCenter(find.text('Profile card')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Profile card'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Profile card'), findsNothing);
  });

  testWidgets('a long press opens it; a tap is the link\'s', (tester) async {
    var went = 0;
    await tester.pumpWidget(
      AshlarApp(
        home: Center(
          child: HoverCard(
            content: (context) => const Text('Joined in March 2024.'),
            child: Button(
              variant: ButtonVariant.link,
              onPressed: () => went++,
              child: const Text('@achieng'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('@achieng'));
    await tester.pumpAndSettle();
    expect(went, 1);
    expect(find.text('Joined in March 2024.'), findsNothing);
    await tester.longPress(find.text('@achieng'));
    await tester.pumpAndSettle();
    expect(find.text('Joined in March 2024.'), findsOneWidget);
    expect(went, 1);
    // A tap elsewhere closes it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Joined in March 2024.'), findsNothing);
  });
}
