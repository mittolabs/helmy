// Tests for PromptInput. Copied into your app by `ashlar add prompt-input` with the
// component: they check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/prompt_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(
  home: Padding(padding: const EdgeInsets.all(16), child: child),
);

void main() {
  group('PromptInput', () {
    testWidgets('sends the text with Enter, trimmed, and empties itself', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(app(PromptInput(onSubmit: sent.add)));
      await tester.enterText(find.byType(EditableText), '  How far is the airport?  ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sent, ['How far is the airport?']);
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
    });

    testWidgets('leaves Shift+Enter to start a new line', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(app(PromptInput(onSubmit: sent.add)));
      await tester.enterText(find.byType(EditableText), 'First line');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(sent, isEmpty);
    });

    testWidgets('sends nothing at all, and says so by its button', (tester) async {
      final handle = tester.ensureSemantics();
      final sent = <String>[];
      await tester.pumpWidget(app(PromptInput(onSubmit: sent.add)));
      await tester.enterText(find.byType(EditableText), '   ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, isEmpty);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Send')),
        matchesSemantics(label: 'Send', isButton: true, hasEnabledState: true, isFocusable: false),
      );
      handle.dispose();
    });

    testWidgets('sends with its button', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(app(PromptInput(onSubmit: sent.add)));
      await tester.enterText(find.byType(EditableText), 'Hello');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      expect(sent, ['Hello']);
    });

    testWidgets('stops instead of sending while busy', (tester) async {
      final sent = <String>[];
      var stopped = 0;
      await tester.pumpWidget(
        app(PromptInput(onSubmit: sent.add, busy: true, onStop: () => stopped++)),
      );
      await tester.enterText(find.byType(EditableText), 'Again');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, isEmpty);
      expect(find.bySemanticsLabel('Send'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Stop'));
      expect(stopped, 1);
    });

    testWidgets('sends an attachment with no text, and shows its actions', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(
        app(
          PromptInput(
            onSubmit: sent.add,
            attachments: const [Text('report.pdf')],
            actions: const [Text('Attach')],
          ),
        ),
      );
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('Attach'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Send'));
      expect(sent, ['']);
    });

    testWidgets('is called by its placeholder to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(PromptInput(onSubmit: (_) {}, placeholder: 'Ask about an order')),
      );
      expect(find.bySemanticsLabel('Ask about an order'), findsOneWidget);
      handle.dispose();
    });
  });
}
