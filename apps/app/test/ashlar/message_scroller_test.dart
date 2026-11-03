// Tests for Message Scroller. Copied into your app by `ashlar add message-scroller` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/message_scroller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {TextDirection direction = TextDirection.ltr}) => AshlarApp(
  builder: (context, page) => Directionality(textDirection: direction, child: page!),
  home: child,
);

/// A row of a known height, named by its id.
MessageScrollerItem row(String id, double height, {bool anchor = false}) => MessageScrollerItem(
  id: id,
  anchor: anchor,
  child: SizedBox(height: height, child: Text(id)),
);

void main() {
  group('Message Scroller', () {
    Future<MessageScrollerController> pump(
      WidgetTester tester,
      List<MessageScrollerItem> items, {
      MessageScrollStart start = MessageScrollStart.lastAnchor,
    }) async {
      final controller = MessageScrollerController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: MessageScroller(
                controller: controller,
                start: start,
                gap: 0,
                padding: EdgeInsets.zero,
                items: items,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    double topOf(WidgetTester tester, String id) =>
        tester.getTopLeft(find.text(id)).dy - tester.getTopLeft(find.byType(MessageScroller)).dy;

    testWidgets('opens at the last turn when it is longer than the view', (tester) async {
      await pump(tester, [
        for (var i = 0; i < 10; i++) row('old $i', 100),
        row('question', 60, anchor: true),
        row('long answer', 600),
      ]);
      // The question near the top, its answer below: not the very end.
      expect(topOf(tester, 'question'), closeTo(64, 1));
    });

    testWidgets('opens at the end when the last turn fits', (tester) async {
      await pump(tester, [
        for (var i = 0; i < 10; i++) row('old $i', 100),
        row('question', 60, anchor: true),
        row('short answer', 100),
      ]);
      expect(
        tester.getBottomLeft(find.text('short answer')).dy,
        closeTo(tester.getBottomLeft(find.byType(MessageScroller)).dy, 1),
      );
    });

    testWidgets('a new turn rises near the top, the row before it peeking above', (tester) async {
      final items = [for (var i = 0; i < 10; i++) row('old $i', 100)];
      await pump(tester, items);
      await pump(tester, [...items, row('new question', 60, anchor: true)]);
      // 64 of the row before stays in view; room is kept below to read from the top.
      expect(topOf(tester, 'new question'), closeTo(64, 1));
      expect(find.text('old 9'), findsOneWidget);
    });

    testWidgets('it follows a growing answer only while the reader is at the end', (tester) async {
      final items = [for (var i = 0; i < 10; i++) row('old $i', 100)];
      await pump(tester, [...items, row('q', 40, anchor: true), row('a', 50)]);
      // The answer streams in, longer than the view: the reader is carried along.
      await pump(tester, [...items, row('q', 40, anchor: true), row('a', 900)]);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('a')).dy,
        closeTo(tester.getBottomLeft(find.byType(MessageScroller)).dy, 1),
      );
      // The reader scrolls up to read: more streams in, and they stay put.
      await tester.drag(find.byType(MessageScroller), const Offset(0, 200));
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('a')).dy;
      await pump(tester, [...items, row('q', 40, anchor: true), row('a', 1200)]);
      expect(tester.getTopLeft(find.text('a')).dy, closeTo(before, 1));
    });

    testWidgets('a turn sent from far up is brought into view', (tester) async {
      final items = [for (var i = 0; i < 30; i++) row('old $i', 100)];
      final controller = await pump(tester, items, start: MessageScrollStart.start);
      expect(controller.canScrollEnd, isTrue);
      // Sent while reading the start: the new turn is far below anything laid out.
      await pump(tester, [...items, row('q', 40, anchor: true), row('a', 50)]);
      await tester.pumpAndSettle();
      expect(find.text('q'), findsOneWidget);
      expect(topOf(tester, 'q'), lessThan(120));
    });

    testWidgets('older messages load above without moving the view', (tester) async {
      final items = [for (var i = 10; i < 20; i++) row('m $i', 100)];
      await pump(tester, items, start: MessageScrollStart.start);
      final at = topOf(tester, 'm 11');
      await pump(tester, [
        for (var i = 0; i < 10; i++) row('m $i', 100),
        ...items,
      ], start: MessageScrollStart.start);
      expect(topOf(tester, 'm 11'), closeTo(at, 1));
      expect(find.text('m 9'), findsNothing);
    });

    testWidgets('jumps to a message not yet built, and tells which turn shows', (tester) async {
      final controller = await pump(tester, [
        for (var i = 0; i < 200; i++) row('m $i', 100, anchor: i % 10 == 0),
      ], start: MessageScrollStart.end);
      expect(find.text('m 30'), findsNothing);
      expect(controller.scrollToMessage('m 30'), isTrue);
      await tester.pumpAndSettle();
      expect(topOf(tester, 'm 30'), closeTo(0, 1));
      expect(controller.currentAnchor, 'm 30');
      expect(controller.visible.first, 'm 30');
      expect(controller.scrollToMessage('nobody'), isFalse);
    });

    testWidgets('the button shows only with more below, and takes you there', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, [
        for (var i = 0; i < 20; i++) row('m $i', 100),
      ], start: MessageScrollStart.end);
      expect(find.semantics.byLabel('Scroll to end'), findsNothing);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(tester.getCenter(find.byType(MessageScroller))));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -600)));
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('Scroll to end'), findsOne);
      await tester.tap(find.bySemanticsLabel('Scroll to end'));
      await tester.pumpAndSettle();
      expect(find.text('m 19'), findsOneWidget);
      expect(find.semantics.byLabel('Scroll to end'), findsNothing);
      semantics.dispose();
    });
  });
}
