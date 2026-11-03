// Tests for Dropdown Menu. Copied into your app by `ashlar add dropdown-menu` with the component: they
// check what it promises, so change them as you change it.
import 'dart:ui' show CheckedState, SemanticsRole;

import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/dropdown_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      themeMode: mode,
      home: Center(child: child),
    );

Widget app2(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  group('Dropdown Menu', () {
    Future<List<String>> open(WidgetTester tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        app(
          DropdownMenu(
            builder: (context, menu) =>
                Button(onPressed: menu.open, child: const Text('Open')),
            items: [
              const MenuLabel(child: Text('My account')),
              MenuItem(
                onPressed: () => picked.add('profile'),
                child: const Text('Profile'),
              ),
              MenuItem(onPressed: null, child: const Text('Billing')),
              const MenuSeparator(),
              MenuItem(
                destructive: true,
                onPressed: () => picked.add('out'),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      return picked;
    }

    testWidgets('a tap on an item calls it and closes the menu', (
      tester,
    ) async {
      final picked = await open(tester);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(picked, ['out']);
      expect(find.text('Profile'), findsNothing);
    });

    testWidgets('the arrow keys skip a disabled item; Enter picks', (
      tester,
    ) async {
      final picked = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, ['out']);
    });

    testWidgets('Escape and a tap outside close it', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
    });

    testWidgets('it opens under the trigger and stays on screen', (
      tester,
    ) async {
      await open(tester);
      final trigger = tester.getRect(find.byType(Button));
      final menu = tester.getRect(find.byType(MenuList));
      expect(menu.top, greaterThanOrEqualTo(trigger.bottom));
      expect(menu.left, closeTo(trigger.left, 1));
    });
  });

  group('Menu items', () {
    Future<Map<String, Object?>> menu(WidgetTester tester) async {
      final state = <String, Object?>{
        'bar': true,
        'pos': 'top',
        'picked': null,
      };
      await tester.pumpWidget(
        app2(
          StatefulBuilder(
            builder: (context, set) => DropdownMenu(
              builder: (context, m) =>
                  Button(onPressed: m.open, child: const Text('Open')),
              items: [
                const MenuLabel(inset: true, child: Text('View')),
                MenuCheckboxItem(
                  checked: state['bar']! as bool,
                  onChanged: (v) => set(() => state['bar'] = v),
                  child: const Text('Status bar'),
                ),
                const MenuSeparator(),
                MenuRadioGroup<String>(
                  value: state['pos'] as String?,
                  onChanged: (v) => set(() => state['pos'] = v),
                  children: const [
                    MenuRadioItem(value: 'top', child: Text('Top')),
                    MenuRadioItem(value: 'bottom', child: Text('Bottom')),
                  ],
                ),
                MenuItem(
                  inset: true,
                  onPressed: () => set(() => state['picked'] = 'plain'),
                  child: const Text('Plain'),
                ),
                MenuSub(
                  items: [
                    MenuItem(
                      onPressed: () => set(() => state['picked'] = 'email'),
                      child: const Text('Email'),
                    ),
                    MenuItem(
                      onPressed: () => set(() => state['picked'] = 'link'),
                      child: const Text('Copy link'),
                    ),
                  ],
                  child: const Text('Share'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets(
      'a checkbox item flips, says whether it is checked, and closes the menu',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final state = await menu(tester);
        final node = tester
            .getSemantics(find.text('Status bar'))
            .getSemanticsData();
        expect(node.flagsCollection.isChecked, CheckedState.isTrue);
        expect(node.role, SemanticsRole.menuItemCheckbox);
        await tester.tap(find.text('Status bar'));
        await tester.pumpAndSettle();
        expect(state['bar'], isFalse);
        expect(find.text('Status bar'), findsNothing);
        semantics.dispose();
      },
    );

    testWidgets(
      'a radio item picks one, and the inset lines labels up with them',
      (tester) async {
        final state = await menu(tester);
        expect(
          tester.getTopLeft(find.text('View')).dx,
          tester.getTopLeft(find.text('Top')).dx,
        );
        expect(
          tester.getTopLeft(find.text('Plain')).dx,
          tester.getTopLeft(find.text('Top')).dx,
        );
        await tester.tap(find.text('Bottom'));
        await tester.pumpAndSettle();
        expect(state['pos'], 'bottom');
      },
    );

    testWidgets(
      'a submenu opens on hover beside its row; picking in it closes everything',
      (tester) async {
        final state = await menu(tester);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Share')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(find.text('Email'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Email')).dx,
          greaterThan(tester.getTopRight(find.text('Share')).dx),
        );
        // Moving to another row of the first menu closes it.
        await mouse.moveTo(tester.getCenter(find.text('Plain')));
        await tester.pumpAndSettle();
        expect(find.text('Email'), findsNothing);
        await mouse.moveTo(tester.getCenter(find.text('Share')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy link'));
        await tester.pumpAndSettle();
        expect(state['picked'], 'link');
        expect(find.text('Share'), findsNothing);
      },
    );

    testWidgets(
      'from the keyboard: right opens the submenu on its first item, left comes back',
      (tester) async {
        final state = await menu(tester);
        // Down to Share: the checkbox, two radios, Plain, Share.
        for (var i = 0; i < 5; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('Email'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text('Email'), findsNothing);
        expect(find.text('Share'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(state['picked'], 'email');
      },
    );
  });
}
