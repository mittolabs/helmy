import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/lesson_repository.dart';
import 'package:helmy/data/services/learner.dart';
import 'package:helmy/domain/models/chat_item.dart';

Lesson _l(String text, String scope) =>
    Lesson(id: text, text: text, scope: scope, kind: 'habit', learnedAt: DateTime(2026));

void main() {
  test("a learner's answer is read, and anything else is not taken as one", () {
    final found = Learner.parse(
      'Here: {"lessons": [{"text": "Check changes in the running app.", "everywhere": true, '
      '"kind": "correction"}, {"text": "Run make test here.", "everywhere": false, "kind": "worked"}]}',
    )!;
    expect(found.map((f) => (f.text, f.everywhere, f.kind)), [
      ('Check changes in the running app.', true, 'correction'),
      ('Run make test here.', false, 'worked'),
    ]);
    expect(Learner.parse('{"lessons": []}'), isEmpty);
    expect(Learner.parse('nothing to learn'), isNull);
  });

  test('a thread starts with the lessons for everywhere and for its project', () async {
    final repo = LessonRepository(null);
    await repo.add(_l('No em dashes.', everywhere));
    await repo.add(_l('Use fvm here.', '/code/app'));
    await repo.add(_l('Deploy with make deploy.', '/code/other'));
    final text = LessonRepository.asInstructions(repo.forProject('/code/app'));
    expect(text, contains('- No em dashes.'));
    expect(text, contains('- Use fvm here.'));
    expect(text, isNot(contains('make deploy')));
    expect(LessonRepository.asInstructions(const []), isEmpty);
  });

  test('a lesson said in the chat is kept with it, and its Undo too', () {
    final item = Learned('id1', 'Check in the running app.')..undone = true;
    final back = ChatItem.fromJson(item.toJson()) as Learned;
    expect((back.lessonId, back.text, back.undone), ('id1', 'Check in the running app.', true));
  });
}
