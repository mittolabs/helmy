// Tests for Questionnaire. Copied into your app by `ashlar add questionnaire` with the component: they
// check what it promises, so change them as you change it.
import 'dart:ui' show CheckedState;

import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/questionnaire.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _questions = [
  Question(
    name: 'size',
    prompt: 'How big is your team?',
    required: true,
    choices: [
      QuestionChoice('small', '1 to 10'),
      QuestionChoice('medium', '11 to 50'),
      QuestionChoice('large', 'More than 50'),
    ],
  ),
  Question(
    name: 'tools',
    prompt: 'What do you use?',
    multiple: true,
    choices: [
      QuestionChoice('flutter', 'Flutter'),
      QuestionChoice('react', 'React'),
    ],
    other: 'Something else',
  ),
  Question(name: 'notes', prompt: 'Anything else?', other: 'Notes'),
];

Future<List<Map<String, QuestionAnswer>>> pump(
  WidgetTester tester, {
  List<Question> questions = _questions,
  QuestionShortcuts shortcuts = QuestionShortcuts.none,
}) async {
  final sent = <Map<String, QuestionAnswer>>[];
  await tester.pumpWidget(
    AshlarApp(
      home: Center(
        child: SizedBox(
          width: 480,
          child: Questionnaire(
            questions: questions,
            shortcuts: shortcuts,
            onSubmit: sent.add,
          ),
        ),
      ),
    ),
  );
  return sent;
}

void main() {
  testWidgets('a required question will not go on unanswered', (tester) async {
    await pump(tester);
    expect(find.text('Question 1 of 3'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an answer to go on.'), findsOneWidget);
    expect(find.text('How big is your team?'), findsOneWidget);
    // Focus is back on the answers, to put it right.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Choice');
    await tester.tap(find.text('11 to 50'));
    await tester.pump();
    expect(find.text('Choose an answer to go on.'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('What do you use?'), findsOneWidget);
    expect(find.text('Question 2 of 3'), findsOneWidget);
  });

  testWidgets(
    'several picks, words of one\'s own, a skip, then everything is sent',
    (tester) async {
      final sent = await pump(tester);
      await tester.tap(find.text('1 to 10'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flutter'));
      await tester.tap(find.text('React'));
      await tester.tap(find.text('React'));
      await tester.enterText(find.byType(EditableText), 'Dart on the server');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Submit'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single['size']!.picked, {'small'});
      expect(sent.single['tools']!.picked, {'flutter'});
      expect(sent.single['tools']!.text, 'Dart on the server');
      expect(sent.single['notes']!.skipped, isTrue);
    },
  );

  testWidgets('back keeps the answer given', (tester) async {
    await pump(tester);
    await tester.tap(find.text('More than 50'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    final node = tester.getSemantics(find.text('More than 50'));
    expect(
      node.getSemanticsData().flagsCollection.isChecked,
      CheckedState.isTrue,
    );
    expect(
      node.getSemanticsData().flagsCollection.isInMutuallyExclusiveGroup,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('letters pick, Enter goes on, arrows move and pick', (
    tester,
  ) async {
    final sent = await pump(tester, shortcuts: QuestionShortcuts.letters);
    expect(find.text('A'), findsOneWidget);
    // Tab reaches the question; nothing is picked yet.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    // Up from nothing focused lands on the last answer and picks it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('What do you use?'), findsOneWidget);
    // Ctrl+Enter from anywhere: this one is optional, so it goes on.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Anything else?'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(sent.single['size']!.picked, {'medium'});
  });

  testWidgets('a question that does not apply is passed over and not counted', (
    tester,
  ) async {
    final questions = [
      const Question(
        name: 'team',
        prompt: 'Do you work in a team?',
        required: true,
        choices: [QuestionChoice('yes', 'Yes'), QuestionChoice('no', 'No')],
      ),
      Question(
        name: 'size',
        prompt: 'How big is it?',
        choices: const [QuestionChoice('small', 'Small')],
        applies: (a) => a['team']?.picked.contains('yes') ?? false,
      ),
      const Question(name: 'notes', prompt: 'Anything else?', other: 'Notes'),
    ];
    final sent = await pump(tester, questions: questions);
    expect(find.text('Question 1 of 2'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Anything else?'), findsOneWidget);
    expect(find.text('Question 2 of 2'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(sent.single.keys, ['team', 'notes']);
  });
}
