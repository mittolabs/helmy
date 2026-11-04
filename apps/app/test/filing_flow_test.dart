import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/turn_log.dart';
import 'package:helmy/domain/filing.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ChatRepository chats;
  late ConversationRepositoryEngines repo;
  late TurnLog log;

  Future<Session> thread(String title, {String? chatId}) async =>
      (await sessions.create(cwd: '/w', title: title, chatId: chatId) as Ok).value as Session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('filing');
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
    // Earlier chats: finances, and an app.
    final budget = await thread('Monthly budget for November');
    await thread('Paying off the car loan', chatId: sessions.byId(budget.id)!.chatId);
    await chats.rename(sessions.byId(budget.id)!.chatId!, 'Finances');
    await thread('Design the Rika onboarding screens');
  });
  tearDown(() async {
    chats.dispose();
    await root.delete(recursive: true);
  });

  Future<ChatViewModel> fresh() async {
    final t = await thread('New session in w');
    repo.of(t.id).loaded = true;
    return ChatViewModel(
      sessionId: t.id,
      sessions: sessions,
      conversations: repo,
      chats: chats,
      log: log,
    );
  }

  String finances() => chats.chats.firstWhere((c) => c.title == 'Finances').id;

  test('a thread about a chat goes into it, said once, and can be taken back', () async {
    final vm = await fresh();
    addTearDown(vm.dispose);
    await vm.send.execute("What's left in my budget this month after the car loan?");
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(vm.session!.chatId, finances());
    expect(vm.filing?.kind, FilingKind.file);
    expect(vm.chatTitle, 'Finances');

    await vm.undoFiling();
    expect(vm.session!.chatId, isNot(finances()));
    expect(vm.filing, isNull);
    final lines = await log.read('2026-11');
    expect(
      [for (final l in lines) l['kind'] == 'filing' ? l['decided'] : l['what']],
      ['file', 'undo'],
    );
  });

  test('about two chats at once: asked, and the answer files it', () async {
    final vm = await fresh();
    addTearDown(vm.dispose);
    final rika = chats.chats.firstWhere((c) => c.title.contains('Rika')).id;
    await vm.send.execute('Rika onboarding and the monthly budget');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(vm.filing?.kind, FilingKind.ask);
    expect({vm.filing?.best, vm.filing?.runnerUp}, {rika, finances()});
    expect(chats.threadsOf(vm.session!.chatId!).length, 1, reason: 'not filed until answered');
    await vm.fileInto(rika);
    expect(vm.session!.chatId, rika);
  });

  test('nothing alike, or a thread started in a chat: left where it is', () async {
    final vm = await fresh();
    addTearDown(vm.dispose);
    final own = vm.session!.chatId;
    await vm.send.execute('Write a haiku about rain on a tin roof');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((vm.session!.chatId, vm.filing), (own, null));

    final inChat = await thread('New session in w', chatId: finances());
    repo.of(inChat.id).loaded = true;
    final vm2 = ChatViewModel(
      sessionId: inChat.id,
      sessions: sessions,
      conversations: repo,
      chats: chats,
      log: log,
    );
    addTearDown(vm2.dispose);
    await vm2.send.execute('Design the Rika onboarding screens');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(vm2.session!.chatId, finances(), reason: 'started in a chat, it stays');
  });
}
