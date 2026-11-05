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
import 'package:helmy/data/services/turn_log.dart';
import 'package:helmy/domain/identity.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

/// The model on this Mac, as given: or none.
class _Writer extends LocalWriter {
  _Writer(this.answers) : super(model: () => null);
  final List<String>? answers;
  var asked = 0;

  @override
  Future<String?> model() async => answers == null ? null : 'qwen3:0.6b';

  @override
  Future<Written?> write(
    String prompt, {
    int maxTokens = 400,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final a = answers;
    if (a == null || asked >= a.length) return null;
    return (text: a[asked++], model: 'qwen3:0.6b', promptTokens: 300, outputTokens: 40);
  }
}

void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ChatRepository chats;
  late ConversationRepositoryEngines repo;
  late TurnLog log;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('keeper');
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
    log = TurnLog(appData: () async => root, now: () => DateTime.utc(2026, 11, 4));
  });
  tearDown(() async {
    chats.dispose();
    await root.delete(recursive: true);
  });

  Future<Session> talk(String said, String answered) async {
    final s = (await sessions.create(cwd: '/w', title: said) as Ok).value as Session;
    repo.of(s.id)
      ..loaded = true
      ..items.addAll([UserMessage(said), AssistantText('a:0', answered)]);
    return s;
  }

  test("Helmy's instructions carry the chat's brief, or are as they were", () {
    expect(identityWith(null), helmyIdentity);
    expect(identityWith('  '), helmyIdentity);
    final with_ = identityWith('Decided: a monthly budget.');
    expect(with_, startsWith(helmyIdentity));
    expect(with_, contains('Decided: a monthly budget.'));
  });

  test('a new thread begins with its chat brief, and keeps it', () async {
    final first = await talk('Monthly budget', 'Done.');
    final chatId = sessions.byId(first.id)!.chatId!;
    await chats.setBrief(chatId, 'Decided: 2,000 a month.');
    final t = (await sessions.create(cwd: '/w', chatId: chatId) as Ok).value as Session;
    repo.of(t.id).loaded = true;
    final vm = ChatViewModel(
      sessionId: t.id,
      sessions: sessions,
      conversations: repo,
      chats: chats,
      log: log,
    );
    addTearDown(vm.dispose);
    await vm.send.execute('How much is left?');
    expect(sessions.byId(t.id)!.brief, 'Decided: 2,000 a month.');
    // The chat's brief changes later: this thread keeps the one it began with.
    await chats.setBrief(chatId, 'Decided: 2,500 a month.');
    await vm.send.execute('And now?');
    expect(sessions.byId(t.id)!.brief, 'Decided: 2,000 a month.');
  });

  test('only a brief in its shape is kept; a summary is one clean line', () {
    expect(
      ChatKeeper.briefFrom('Sure! Here it is:\n- Decided: budget\nOpen: car\nThanks'),
      'Decided: budget\nOpen: car',
    );
    expect(ChatKeeper.briefFrom('I cannot help with that.'), isNull);
    expect(
      ChatKeeper.summaryFrom('"Budget for November, nearly settled"\nmore'),
      'Budget for November, nearly settled',
    );
    expect(ChatKeeper.summaryFrom('x' * 200)!.length, 140);
  });

  test('a quiet thread gets its summary, and its chat its brief, on the model here', () async {
    final s = await talk('Plan the November budget', 'Set at 2,000; the car loan is still open.');
    final keeper = ChatKeeper(
      sessions: sessions,
      conversations: repo,
      chats: chats,
      writer: _Writer([
        'November budget, set at 2,000',
        'Decided: budget is 2,000\nOpen: the car loan',
      ]),
      log: log,
    );
    addTearDown(keeper.dispose);
    await keeper.keep(s.id);
    final now = sessions.byId(s.id)!;
    expect(now.summary, 'November budget, set at 2,000');
    expect(chats.byId(now.chatId!)!.brief, 'Decided: budget is 2,000\nOpen: the car loan');
    expect(chats.byId(now.chatId!)!.briefByPerson, isFalse);
    final upkeep = [
      for (final l in await log.read('2026-11'))
        if (l['kind'] == 'upkeep') '${l['what']}:${l['local']}',
    ];
    expect(upkeep, [
      'summary:true',
      'brief:true',
      'describe:false',
    ], reason: 'naming had no answer left');
  });

  test(
    "a brief the person wrote is left as it is; with no model, the thread's own words",
    () async {
      final s = await talk('Plan the November budget', 'Set at 2,000.');
      final chatId = sessions.byId(s.id)!.chatId!;
      await chats.setBrief(chatId, 'Mine: keep it simple.');
      final writer = _Writer(['November budget', 'Decided: something else']);
      final keeper = ChatKeeper(
        sessions: sessions,
        conversations: repo,
        chats: chats,
        writer: writer,
        log: log,
      );
      addTearDown(keeper.dispose);
      await keeper.keep(s.id);
      expect(chats.byId(chatId)!.brief, 'Mine: keep it simple.');
      expect(writer.asked, 2, reason: 'the summary, then naming: the brief is not even asked for');

      final other = await talk('Book the Lisbon flights', 'Booked.');
      final none = ChatKeeper(
        sessions: sessions,
        conversations: repo,
        chats: chats,
        writer: _Writer(null),
        log: log,
      );
      addTearDown(none.dispose);
      await none.keep(other.id);
      expect(sessions.byId(other.id)!.summary, 'Book the Lisbon flights');
      expect(chats.byId(sessions.byId(other.id)!.chatId!)!.brief, isEmpty);
    },
  );

  test('a thread kept busy is kept every fifth turn, its summary ready for a hand-off', () async {
    final s = await talk('Plan the November budget', 'Set at 2,000.');
    final writer = _Writer(List.filled(20, 'Budget, being set'));
    final keeper = ChatKeeper(
      sessions: sessions,
      conversations: repo,
      chats: chats,
      writer: writer,
      log: log,
      quiet: const Duration(hours: 1),
    );
    addTearDown(keeper.dispose);
    final c = repo.of(s.id);
    for (var i = 0; i < 5; i++) {
      c.busy = true;
      repo.notifyListeners();
      c.busy = false;
      repo.notifyListeners();
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sessions.byId(s.id)!.summary, 'Budget, being set');
  });

  test('what the model wrote names a chat: topic from the set, icon, title, about', () {
    final n = ChatKeeper.namingFrom(
      'Topic: Design  \nIcon: logo  \nTitle: Ask EVA logo  \n'
      'About: Logo requested; simulator access still open  \nThread: Logo design',
    );
    expect(n.topic, 'Design');
    expect(n.icon, 'design', reason: 'an icon not in the set: the topic\'s own');
    expect(n.title, 'Ask EVA logo');
    expect(n.about, 'Logo requested; simulator access still open');
    expect(n.thread, 'Logo design');

    final narrated = ChatKeeper.namingFrom(
      'Topic: web\nIcon: search\nTitle: Google images download\n'
      'About: Person asked to download 5 images fast\nThread: Image download',
    );
    expect(narrated.topic, 'Web', reason: 'spelled as the set spells it');
    expect(narrated.about, isNull, reason: 'narrated, not said: dropped');

    final nothing = ChatKeeper.namingFrom(
      'Topic: People\nIcon: person\nTitle: New chat\nAbout:\nThread: Greeting',
    );
    expect(
      (nothing.title, nothing.topic, nothing.icon),
      (null, null, null),
      reason: 'nothing to name yet',
    );

    expect(
      ChatKeeper.namingFrom('Topic: helmy\nTitle: Settle wording', project: 'helmy').topic,
      'helmy',
    );
    expect(
      ChatKeeper.namingFrom('Topic: Gardening\nTitle: Tomatoes').topic,
      isNull,
      reason: 'not in the set',
    );
  });

  test('a chat is named after its first answer, and a person\'s name is kept', () async {
    final s = await talk('what was the last thing i downloaded?', 'report.pdf, on Tuesday.');
    final chatId = sessions.byId(s.id)!.chatId!;
    final keeper = ChatKeeper(
      sessions: sessions,
      conversations: repo,
      chats: chats,
      writer: _Writer([
        'Topic: Files\nIcon: download\nTitle: Recent downloads\nAbout: Last download found: report.pdf\nThread: Finding the last download',
        'Topic: Work\nIcon: work\nTitle: Something else\nAbout: Still report.pdf\nThread: Again',
      ]),
      log: log,
    );
    addTearDown(keeper.dispose);
    await keeper.describe(s.id);
    final chat = chats.byId(chatId)!;
    expect(
      (chat.topic, chat.icon, chat.title, chat.description),
      ('Files', 'download', 'Recent downloads', 'Last download found: report.pdf'),
    );
    expect(
      sessions.byId(s.id)!.title,
      'Finding the last download',
      reason: 'it was only its first words',
    );

    // Named once: later only what it is about changes.
    await chats.rename(chatId, 'Downloads');
    await keeper.describe(s.id);
    final again = chats.byId(chatId)!;
    expect(
      (again.title, again.topic, again.description),
      ('Downloads', 'Files', 'Still report.pdf'),
    );
  });

  test('catching up names chats from before, and calls an empty one New chat', () async {
    final s = await talk('dim my computer screen light', 'Dimmed it.');
    final empty =
        (await sessions.create(cwd: '/w', title: 'New session in w') as Ok).value as Session;
    repo.of(empty.id).loaded = true;
    final keeper = ChatKeeper(
      sessions: sessions,
      conversations: repo,
      chats: chats,
      writer: _Writer([
        'Topic: Computer\nIcon: computer\nTitle: Screen brightness\nAbout: Screen dimmed\nThread: Dimming',
      ]),
      log: log,
      catchUpAfter: const Duration(days: 1),
    );
    addTearDown(keeper.dispose);
    await keeper.catchUp();
    expect(chats.byId(sessions.byId(s.id)!.chatId!)!.title, 'Screen brightness');
    expect(sessions.byId(empty.id)!.title, 'New chat');
  });
}
