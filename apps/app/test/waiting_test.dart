import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_keeper.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/local_writer.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/waiting.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';
import 'support/storage.dart';

/// The model here, answering in turn: the summary, the naming, then
/// whether it waits.
class _Writer extends LocalWriter {
  _Writer(this.answers) : super(model: () => null);
  final List<String> answers;
  final prompts = <String>[];

  @override
  Future<String?> model() async => 'qwen3:8b';

  @override
  Future<Written?> write(
    String prompt, {
    int maxTokens = 400,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    prompts.add(prompt);
    final i = prompts.length - 1;
    if (i >= answers.length) return null;
    return (text: answers[i], model: 'qwen3:8b', promptTokens: 300, outputTokens: 12);
  }
}

/// The end of a real answer that left its chat waiting: on commands the
/// person runs on production and a colleague's reply.
const _handsOver = '''
- The project from your screenshot is in the list: confirmed, that is the collision.
- It is not in the list (or the list is empty): the cause is something else, and the log will name it:

grep -h "production.ERROR" storage/logs/*.log | tail -5 | cut -c1-400

Paste back what either one prints.''';

/// Chats that wait on something outside them: offered, set aside, in sight,
/// and back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('whether an answer hands the next step over', () {
    test('one that asks for what was run elsewhere may wait', () {
      expect(mayWait(_handsOver), isTrue);
      expect(mayWait('Run these on the server and send me the output.'), isTrue);
      expect(mayWait('Once Sam replies, we can pick the venue.'), isTrue);
      expect(mayWait('Ask Debby which project it was.'), isTrue);
    });

    test('one that is simply done does not, and costs no model', () {
      expect(mayWait('Done: the budget is set at 2,000 and saved to budget.md.'), isFalse);
      expect(mayWait('Here is the summary you asked for.'), isFalse);
      expect(mayWait(''), isFalse);
    });

    test("the model's line is read as a short note, or nothing", () {
      expect(waitFrom('Waiting: Debby to say which project'), 'Debby to say which project');
      expect(waitFrom('Waiting: "what the server log prints".'), 'What the server log prints');
      expect(waitFrom('Waiting: no'), isNull);
      expect(waitFrom('Waiting: None'), isNull);
      expect(waitFrom('It does not wait.'), isNull);
      expect(waitFrom('Waiting: the user to run the commands'), 'You to run the commands');
      expect(waitFrom('Waiting: ${'x' * 80}')!.length, 60);
    });
  });

  test('what it waits on is kept with the chat, and cleared with ""', () {
    final s = Session(
      id: 'a',
      title: 'Fix the template',
      cwd: '/w',
      level: .ask,
      createdAt: DateTime(2026, 11, 18),
      updatedAt: DateTime(2026, 11, 18),
      waitingOn: 'Debby to say which project',
      waitOffer: 'Debby to say which project',
    );
    final again = Session.fromJson(s.toJson());
    expect(again.waitingOn, 'Debby to say which project');
    expect(again.waiting, isTrue);
    expect(again.waitOffer, 'Debby to say which project');
    final cleared = again.copyWith(waitingOn: '', waitOffer: '');
    expect(cleared.waiting, isFalse);
    expect(cleared.waitOffer, isNull);
    expect(again.copyWith(title: 'x').waitingOn, 'Debby to say which project', reason: 'kept');
  });

  group('with chats', () {
    late Directory root;
    late SessionRepositoryLocal sessions;
    late ChatRepository chats;
    late ConversationRepositoryEngines repo;
    late SidebarViewModel list;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('waiting');
      final storage = storageAt(root);
      sessions = SessionRepositoryLocal(storage);
      chats = ChatRepository(storage, sessions);
      await chats.load();
      final meter = UsageMeter();
      repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      list = SidebarViewModel(
        sessions: sessions,
        conversations: repo,
        settings: FakeSettingsRepository(),
        chats: chats,
      );
    });
    tearDown(() async {
      list.dispose();
      repo.dispose();
      chats.dispose();
      await deleteFolder(root);
    });

    Future<Session> talk(String said, String answered) async {
      final s = (await sessions.create(cwd: '/w', title: said) as Ok).value as Session;
      repo.of(s.id)
        ..loaded = true
        ..items.addAll([UserMessage(said), AssistantText('a:0', answered)]);
      return sessions.byId(s.id)!;
    }

    ChatKeeper keeper(_Writer w) =>
        ChatKeeper(sessions: sessions, conversations: repo, chats: chats, writer: w);

    test('an answer that waits on something outside is offered to set aside', () async {
      final s = await talk('The template fails to apply', _handsOver);
      final w = _Writer([
        'Template fails to apply; waiting on production output',
        'Title: Template apply error\nAbout: cause narrowed down\nThread: Template apply',
        'Waiting: Debby to say which project',
      ]);
      final k = keeper(w);
      addTearDown(k.dispose);
      await k.keep(s.id);
      expect(w.prompts.last, contains('Waiting: <who or what'));
      expect(sessions.byId(s.id)!.waitOffer, 'Debby to say which project');
    });

    test('one the model says waits on nothing is offered nothing', () async {
      final s = await talk('The template fails to apply', _handsOver);
      final k = keeper(_Writer(['A summary', 'Title: Template', 'Waiting: no']));
      addTearDown(k.dispose);
      await k.keep(s.id);
      expect(sessions.byId(s.id)!.waitOffer, isNull);
    });

    test('an answer that hands nothing over is not asked about, so costs nothing', () async {
      final s = await talk('Set the budget', 'Done: set at 2,000 and saved.');
      final w = _Writer(['Budget set at 2,000', 'Title: Budget']);
      final k = keeper(w);
      addTearDown(k.dispose);
      await k.keep(s.id);
      expect(w.prompts.where((p) => p.contains('Waiting: <who or what')), isEmpty);
    });

    test('set aside, it leaves the list for Waiting, says why, and never settles', () async {
      final s = await talk('The template fails to apply', _handsOver);
      final other = await talk('Plan the launch', 'Done.');
      final until = DateTime.now().add(const Duration(hours: 18));
      await list.waitChat(list.chatOf(s), 'Debby to say which project', until);
      expect(list.inOrder.map((x) => x.id), [other.id], reason: 'out of the list');
      expect([for (final e in list.waiting) e.threads.first.id], [s.id], reason: 'in sight');
      final waiting = sessions.byId(s.id)!;
      expect(waiting.waitOffer, isNull, reason: 'the offer is taken');
      expect(
        SidebarViewModel.waitingLine(waiting, now: until.subtract(const Duration(hours: 18))),
        startsWith('Debby to say which project · back '),
      );
      // However long it waits, it does not settle on its own.
      await list.settleIdle(now: DateTime.now().add(const Duration(days: 30)));
      expect(chats.byId(waiting.chatId!)!.settled, isFalse);
      // ⌘Z: back as it was.
      await list.undo();
      expect(sessions.byId(s.id)!.waiting, isFalse);
      expect(list.waiting, isEmpty);
    });

    test(
      "taken from the chat's offer, the whole chat waits; writing in it brings it back",
      () async {
        final s = await talk('The template fails to apply', _handsOver);
        await sessions.save(sessions.byId(s.id)!.copyWith(waitOffer: 'Debby to say which project'));
        final vm = ChatViewModel(sessionId: s.id, sessions: sessions, conversations: repo);
        addTearDown(vm.dispose);
        expect(vm.waitOffer, 'Debby to say which project');
        await vm.setAside(vm.waitOffer!, DateTime.now().add(const Duration(hours: 18)));
        expect(vm.waitOffer, isNull, reason: 'taken');
        expect(sessions.byId(s.id)!.waiting, isTrue);
        expect([for (final e in list.waiting) e.threads.first.id], [s.id]);
        // The reply came: written in, it is back, nothing waiting.
        await vm.send.execute('It is JayKay, project 68');
        final back = sessions.byId(s.id)!;
        expect(back.waiting, isFalse);
        expect(back.snoozed, isFalse);
        expect(list.waiting, isEmpty);
      },
    );

    test("waved off, the chat's offer is gone", () async {
      final s = await talk('The template fails to apply', _handsOver);
      await sessions.save(sessions.byId(s.id)!.copyWith(waitOffer: 'Debby to say which project'));
      final vm = ChatViewModel(sessionId: s.id, sessions: sessions, conversations: repo);
      addTearDown(vm.dispose);
      await vm.dismissWaitOffer();
      expect(vm.waitOffer, isNull);
      expect(sessions.byId(s.id)!.waitOffer, isNull);
    });

    test('woken, it is back in the list still saying what it waited on', () async {
      final s = await talk('The template fails to apply', _handsOver);
      await list.waitChat(list.chatOf(s), 'Debby to say which project', DateTime(2026, 11, 19, 9));
      await list.wakeChat(list.chatOf(sessions.byId(s.id)!));
      final back = sessions.byId(s.id)!;
      expect(back.snoozed, isFalse);
      expect(back.waiting, isTrue, reason: 'until the person writes in it');
      expect(SidebarViewModel.waitingLine(back), 'Debby to say which project');
      expect(list.inOrder.map((x) => x.id), contains(s.id));
    });
  });

  test('the times a chat can come back, tomorrow first', () {
    final choices = SidebarViewModel.waitChoices(DateTime(2026, 11, 18, 14));
    expect(choices.first.$1, 'Until tomorrow');
    expect(choices.first.$2, DateTime(2026, 11, 19, 9));
    expect(choices.map((c) => c.$1), contains('For an hour'));
  });
}
