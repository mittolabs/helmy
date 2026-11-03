import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/ashlar/message_scroller.dart';

class _Chat extends StatefulWidget {
  const _Chat();
  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  double last = 300;
  void grow() => setState(() => last += 1);
  @override
  Widget build(BuildContext context) => MessageScroller(
    items: [
      for (var i = 0; i < 6; i++)
        MessageScrollerItem(
          id: i,
          child: SizedBox(height: 200, child: Text('row $i')),
        ),
      MessageScrollerItem(
        id: 'last',
        child: SizedBox(height: last),
      ),
    ],
  );
}

/// Found 2026-11-03 from the owner's debug log: scrolling up from the end, the
/// first pixel still counted as "at the end", a size change in that moment
/// queued a jump to the end, and the jump ran after the reader had moved away.
/// The page flickered back on every try.
void main() {
  testWidgets('scrolling up from the end is not pulled back when the content changes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AshlarApp(theme: appTheme, darkTheme: appDarkTheme, home: const _Chat()),
    );
    await tester.pumpAndSettle();
    final pos = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final chat = tester.state<_ChatState>(find.byType(_Chat));
    expect(pos.pixels, pos.maxScrollExtent);

    final pad = TestPointer(1, PointerDeviceKind.trackpad);
    const at = Offset(450, 300);
    await tester.sendEventToBinding(pad.panZoomStart(at));
    await tester.sendEventToBinding(pad.panZoomUpdate(at, pan: const Offset(0, 1)));
    await tester.pump(const Duration(milliseconds: 16));
    chat.grow();
    for (var k = 1; k <= 8; k++) {
      await tester.sendEventToBinding(pad.panZoomUpdate(at, pan: Offset(0, 1 + 15.0 * k)));
      await tester.pump(const Duration(milliseconds: 16));
      if (k == 2) chat.grow();
    }
    await tester.sendEventToBinding(pad.panZoomEnd());
    await tester.pumpAndSettle();
    expect(pos.pixels, lessThan(pos.maxScrollExtent - 60));
    debugDefaultTargetPlatformOverride = null;
  });
}
