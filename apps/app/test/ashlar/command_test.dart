// Tests for Command. Copied into your app by `ashlar add command` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/command.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  group('Command', () {
    Future<List<String>> command(WidgetTester tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 400,
            child: Command(
              groups: [
                CommandGroup(heading: 'Suggestions', [
                  CommandItem('Calendar', onSelected: () => picked.add('calendar')),
                  CommandItem(
                    'Calculator',
                    enabled: false,
                    onSelected: () => picked.add('calculator'),
                  ),
                  CommandItem('Search emoji', onSelected: () => picked.add('emoji')),
                ]),
                CommandGroup(heading: 'Settings', [
                  CommandItem(
                    'Billing',
                    keywords: ['invoice', 'payment'],
                    onSelected: () => picked.add('billing'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      return picked;
    }

    testWidgets('typing narrows the list, by label or keyword', (tester) async {
      await command(tester);
      await tester.enterText(find.byType(EditableText), 'cal');
      await tester.pump();
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Search emoji'), findsNothing);
      expect(find.text('Settings'), findsNothing);
      await tester.enterText(find.byType(EditableText), 'invoice');
      await tester.pump();
      expect(find.text('Billing'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'zzz');
      await tester.pump();
      expect(find.text('No results found.'), findsOneWidget);
    });

    testWidgets(
      'the arrows move the highlight past what is off, Enter picks, and the box keeps the typing',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final picked = await command(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(find.bySemanticsLabel('Search emoji'), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(picked, ['emoji']);
        expect(
          FocusManager.instance.primaryFocus!.context!
              .findAncestorWidgetOfExactType<EditableText>(),
          isNotNull,
        );
        semantics.dispose();
      },
    );

    testWidgets('as a dialog, picking closes it first', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Button(
              onPressed: () => showCommandDialog(
                context: context,
                groups: [
                  CommandGroup([CommandItem('Profile', onSelected: () => picked.add('profile'))]),
                ],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, ['profile']);
      expect(find.text('Profile'), findsNothing);
    });
  });
}
