// Tests for Bubble. Copied into your app by `ashlar add bubble` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/bubble.dart';
import 'package:helmy/ui/core/ashlar/message.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    AshlarApp(
      builder: (context, page) =>
          Directionality(textDirection: direction, child: page!),
      home: child,
    );

void main() {
  group('Message and Bubble', () {
    for (final direction in TextDirection.values) {
      testWidgets(
        'what you sent sits at the end of the line, ${direction.name}',
        (tester) async {
          await tester.pumpWidget(
            app(
              const SizedBox(
                width: 400,
                child: Column(
                  children: [
                    Message(child: Bubble(child: Text('Theirs'))),
                    Message(
                      align: MessageAlign.end,
                      avatar: SizedBox.square(dimension: 32, child: Text('ME')),
                      child: Bubble(child: Text('Mine')),
                    ),
                  ],
                ),
              ),
              direction: direction,
            ),
          );
          final theirs = tester.getCenter(find.text('Theirs')).dx;
          final mine = tester.getCenter(find.text('Mine')).dx;
          final me = tester.getCenter(find.text('ME')).dx;
          if (direction == TextDirection.ltr) {
            expect(mine, greaterThan(theirs));
            expect(me, greaterThan(mine));
          } else {
            expect(mine, lessThan(theirs));
            expect(me, lessThan(mine));
          }
        },
      );
    }

    testWidgets('a bubble is no wider than four fifths of the room', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox(
              width: 500,
              child: Message(child: Bubble(child: Text('word ' * 80))),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(Bubble)).width, lessThanOrEqualTo(400));
    });

    testWidgets('reactions sit over the edge without covering what follows', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Bubble(reactions: Text('+2'), child: Text('Shipped')),
              Text('Next'),
            ],
          ),
        ),
      );
      final reaction = tester.getRect(find.text('+2'));
      final next = tester.getRect(find.text('Next'));
      expect(reaction.bottom, lessThanOrEqualTo(next.top));
      // Clear of the message's text, yet still over the bubble's edge.
      final text = tester.getRect(find.text('Shipped'));
      expect(reaction.top, greaterThan(text.bottom));
      expect(reaction.top, lessThan(text.bottom + 20));
    });

    testWidgets('a bubble with onPressed is a button', (tester) async {
      var taps = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          Center(
            child: Bubble(
              variant: BubbleVariant.outline,
              onPressed: () => taps++,
              child: const Text('Yes, book it'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Yes, book it'));
      expect(taps, 1);
      expect(
        tester
            .getSemantics(find.text('Yes, book it'))
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
      );
      semantics.dispose();
    });
  });
}
