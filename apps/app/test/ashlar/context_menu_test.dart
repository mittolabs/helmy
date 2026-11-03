// Tests for Context Menu. Copied into your app by `ashlar add context-menu` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/context_menu.dart';
import 'package:helmy/ui/core/ashlar/dropdown_menu.dart';
import 'package:helmy/ui/core/ashlar/popover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  group('Context Menu', () {
    Future<List<String>> menu(WidgetTester tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        app(
          ContextMenu(
            items: [
              MenuItem(onPressed: () => picked.add('back'), child: const Text('Back')),
              MenuItem(onPressed: () => picked.add('reload'), child: const Text('Reload')),
            ],
            child: SizedBox(
              width: 300,
              height: 150,
              child: Center(
                child: Button(onPressed: () {}, child: const Text('Area')),
              ),
            ),
          ),
        ),
      );
      return picked;
    }

    testWidgets('a right-click opens it at the pointer; picking closes it', (tester) async {
      final picked = await menu(tester);
      final area = tester.getRect(find.byType(ContextMenu));
      final at = area.topLeft + const Offset(40, 30);
      await tester.tapAt(at, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.descendant(of: find.byType(PopoverPanel), matching: find.byType(TapRegion)).first,
      );
      expect(panel.left, closeTo(at.dx, 1));
      expect(panel.top, closeTo(at.dy + 4, 1));
      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();
      expect(picked, ['reload']);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('a long press opens it, and so does Shift+F10 from the keyboard', (tester) async {
      await menu(tester);
      await tester.longPress(find.byType(ContextMenu));
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsOneWidget);
    });
  });
}
