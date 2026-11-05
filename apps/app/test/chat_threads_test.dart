import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chat_items.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';
import 'support/storage.dart';

/// A chat's threads live inside it (decision 0014): a row per chat, a new
/// thread after a quiet gap, and what is done to a row done to the chat.
void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ChatRepository chats;
  late ConversationRepositoryEngines repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('threads');
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
  });
  tearDown(() async {
    repo.dispose();
    chats.dispose();
    await deleteFolder(root);
  });

  /// A thread with one exchange, last worked in [ago] ago.
  Future<Session> worked(String title, Duration ago, {String? chatId}) async {
    final s =
        (await sessions.create(cwd: '/w', title: title, chatId: chatId) as Ok).value as Session;
    final at = DateTime.now().subtract(ago);
    final dated = Session.fromJson({...s.toJson(), 'updatedAt': at.toIso8601String()});
    await sessions.save(dated);
    repo.of(s.id)
      ..loaded = true
      ..items.addAll([
        UserMessage('Hello')..sentAt = at,
        AssistantText('a', 'Hi.'),
        TurnSummary(ok: true)..endedAt = at,
      ]);
    return sessions.byId(s.id)!;
  }

  test('a new chat is called a chat, and a thread not yet named says so', () async {
    final s = (await sessions.create(cwd: '/w') as Ok).value as Session;
    expect(s.title, 'New chat');
    expect(s.untitled, isTrue);
    expect(s.copyWith(title: 'New thread').untitled, isTrue);
    expect(s.copyWith(title: 'New session in w').untitled, isTrue, reason: 'from before chats');
    expect(s.copyWith(title: 'New sessions of the board').untitled, isFalse);
  });

  test('back after a quiet gap, a message starts a new thread in the same chat', () async {
    final old = await worked('Food budget', const Duration(hours: 7));
    final vm = ChatViewModel(
      sessionId: old.id,
      sessions: sessions,
      conversations: repo,
      chats: chats,
    );
    await vm.ready;
    String? opened;
    vm.openThread.addListener(() => opened = vm.openThread.value);
    await vm.send.execute('What about December?');
    expect(opened, isNotNull, reason: 'the screen goes to the new thread');
    final fresh = sessions.byId(opened!)!;
    expect(fresh.chatId, old.chatId);
    expect(repo.of(fresh.id).items.whereType<UserMessage>().single.text, 'What about December?');
    expect(
      repo.of(old.id).items.whereType<UserMessage>(),
      hasLength(1),
      reason: 'the old one untouched',
    );
    expect(ChatViewModel.startedAfter[fresh.id], old.id);

    // Kept going in the last one instead: the message goes there, the new thread goes.
    final back = ChatViewModel(
      sessionId: fresh.id,
      sessions: sessions,
      conversations: repo,
      chats: chats,
    );
    await back.ready;
    expect(await back.keepGoingInLast(), old.id);
    expect(sessions.byId(fresh.id), isNull);
    expect(repo.of(old.id).items.whereType<UserMessage>().last.text, 'What about December?');
    vm.dispose();
    back.dispose();
  });

  test('within the gap, or in its own working copy, a message stays in the thread', () async {
    final recent = await worked('Food budget', const Duration(hours: 2));
    final vm = ChatViewModel(
      sessionId: recent.id,
      sessions: sessions,
      conversations: repo,
      chats: chats,
    );
    await vm.ready;
    await vm.send.execute('And December?');
    expect(vm.openThread.value, isNull);
    expect(repo.of(recent.id).items.whereType<UserMessage>(), hasLength(2));
    vm.dispose();

    final copy = await worked('Fix upload', const Duration(days: 2));
    await sessions.save(copy.copyWith(repo: '/w', branch: 'fix-upload'));
    final inCopy = ChatViewModel(
      sessionId: copy.id,
      sessions: sessions,
      conversations: repo,
      chats: chats,
    );
    await inCopy.ready;
    await inCopy.send.execute('Try again');
    expect(inCopy.openThread.value, isNull, reason: 'a working copy is one piece of work');
    inCopy.dispose();
  });

  test("a chat's other threads read above, oldest first, each under a separator", () async {
    final a = await worked('Food budget', const Duration(days: 3));
    final b = await worked('Q3 taxes', const Duration(days: 1), chatId: a.chatId);
    final c = await worked('Savings', const Duration(minutes: 5), chatId: a.chatId);
    final vm = ChatViewModel(
      sessionId: c.id,
      sessions: sessions,
      conversations: repo,
      chats: chats,
    );
    await vm.ready;
    expect(vm.earlierThreads.map((t) => t.id), [a.id, b.id]);
    final ids = threadRows(vm).map((r) => r.id).toList();
    expect(ids, ['ts${a.id}', 'tg${a.id}', 'ts${b.id}', 'tg${b.id}', 'ts${c.id}']);
    vm.toggleThread(a.id);
    expect(threadRows(vm).map((r) => r.id), contains('tp${a.id}-0'), reason: 'opened, it reads');
    vm.dispose();
  });

  test('archiving a row archives the chat, and ⌘Z brings all of it back', () async {
    final a = await worked('Food budget', const Duration(days: 3));
    final b = await worked('Q3 taxes', const Duration(days: 1), chatId: a.chatId);
    final list = SidebarViewModel(
      sessions: sessions,
      conversations: repo,
      settings: FakeSettingsRepository(),
      chats: chats,
    );
    await list.setChatArchived(list.chatOf(a), true);
    expect([a, b].map((t) => sessions.byId(t.id)!.archived), [true, true]);
    expect(list.shown, isEmpty);
    await list.undo();
    expect([a, b].map((t) => sessions.byId(t.id)!.archived), [false, false]);
    expect(list.entriesOf(list.shown), hasLength(1));
    list.dispose();
  });

  test('the separator says when: the time today, the date before', () {
    final now = DateTime(2026, 11, 5, 15);
    expect(threadStamp(DateTime(2026, 11, 5, 9, 5), now), '9:05 AM');
    expect(threadStamp(DateTime(2026, 11, 2, 17, 40), now), 'Nov 2, 5:40 PM');
    expect(threadStamp(DateTime(2025, 12, 31, 0, 1), now), 'Dec 31 2025, 12:01 AM');
  });
}
