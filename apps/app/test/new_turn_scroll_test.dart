import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/ashlar/message_scroller.dart';

Widget _app(List<MessageScrollerItem> items) => AshlarApp(
  theme: appTheme,
  darkTheme: appDarkTheme,
  home: MessageScroller(items: items),
);

MessageScrollerItem _user(int i) => MessageScrollerItem(
  id: i,
  anchor: true,
  child: SizedBox(height: 50, child: Text('message $i')),
);

MessageScrollerItem _answer(int i) => MessageScrollerItem(
  id: 'a$i',
  child: SizedBox(height: 900, child: Text('answer $i')),
);

const _working = MessageScrollerItem(
  id: 'working',
  child: SizedBox(height: 30, child: Text('Working')),
);

/// Found 2026-11-10: "Working" reached the list before the message it
/// answers, so the message counted as older history, was laid out above the
/// view, and the person could not see what they had just sent.
void main() {
  for (final (name, steps, sent) in [
    (
      'the first message, after its working row',
      [
        <MessageScrollerItem>[],
        [_working],
        [_user(0), _working],
      ],
      0,
    ),
    (
      'the first message, before its working row',
      [
        <MessageScrollerItem>[],
        [_user(0)],
        [_user(0), _working],
      ],
      0,
    ),
    (
      'a later message, after its working row',
      [
        [_user(0), _answer(0)],
        [_user(0), _answer(0), _working],
        [_user(0), _answer(0), _user(1), _working],
      ],
      1,
    ),
  ]) {
    testWidgets('$name is in view once sent', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final s in steps) {
        await tester.pumpWidget(_app(s));
        await tester.pumpAndSettle();
      }
      final top = tester.getTopLeft(find.text('message $sent')).dy;
      expect(top, inInclusiveRange(0, 200), reason: 'near the top of the view');
    });
  }
}
