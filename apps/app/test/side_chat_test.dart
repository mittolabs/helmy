import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';

void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ConversationRepositoryEngines repo;
  late ChatViewModel vm;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('side');
    final storage = StorageService(root: () async => root);
    sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final main =
        (await sessions.create(cwd: root.path, title: 'Build the site') as Ok).value as Session;
    repo.of(main.id)
      ..loaded = true
      ..items.addAll([UserMessage('Make the home page'), AssistantText('a:0', 'Made it.')]);
    vm = ChatViewModel(sessionId: main.id, sessions: sessions, conversations: repo);
  });
  tearDown(() async {
    vm.dispose();
    await root.delete(recursive: true);
  });

  Future<String> start() async {
    await vm.sideChat();
    return vm.active!.sideId!;
  }

  test('starts from all the session knows, in a tab of its own, out of the list', () async {
    final id = await start();
    final side = sessions.byId(id)!;
    expect(side.sideOf, vm.sessionId);
    expect(side.cwd, root.path);
    final items = repo.of(id).items;
    expect(items.whereType<UserMessage>().single.text, 'Make the home page');
    expect((items.last as Notice).text, sideChatNote);
    expect(vm.active!.kind, SidePanel.side);
    expect(vm.sideTitle(id), 'Side chat', reason: 'until its first question names it');

    // It shows from its note on; what came before is what it knows.
    final sideVm = ChatViewModel(
      sessionId: id,
      sessions: sessions,
      conversations: repo,
      embedded: true,
    );
    addTearDown(sideVm.dispose);
    await sideVm.ready;
    expect(sideVm.firstShown, 2);
    expect(vm.firstShown, 0);
    expect(sideVm.addable, isNot(contains(SidePanel.side)));

    final list = SidebarViewModel(
      sessions: sessions,
      conversations: repo,
      settings: FakeSettingsRepository(),
    );
    addTearDown(list.dispose);
    expect(list.shown.map((s) => s.id), [vm.sessionId]);
    expect(list.sessions.map((s) => s.id), [vm.sessionId]);
    expect(vm.sideChats.single.id, id);
  });

  test('closed with nothing asked, it is deleted; asked in, it stays', () async {
    final unused = await start();
    vm.closeTab(vm.active!);
    await Future<void>.delayed(Duration.zero);
    expect(sessions.byId(unused), isNull);
    expect(vm.tabs, isEmpty);

    final used = await start();
    repo.of(used).items.add(UserMessage('Why blue?'));
    vm.closeTab(vm.active!);
    expect(sessions.byId(used), isNotNull);
    vm.openSide(used);
    expect(vm.active!.sideId, used, reason: 'found again, in its tab');
  });

  test('brought back as a file with the next message, only what was said in it', () async {
    final id = await start();
    repo.of(id).items.addAll([UserMessage('Why blue?'), AssistantText('b:0', 'It matches the logo.')]);
    expect(await vm.bringBack(id), isTrue);
    final file = File(vm.attachments.single);
    final text = file.readAsStringSync();
    expect(text, contains('Why blue?'));
    expect(text, contains('It matches the logo.'));
    expect(text, isNot(contains('Make the home page')), reason: 'the session has that already');

    // Not while the session works.
    repo.of(vm.sessionId).busy = true;
    expect(await vm.bringBack(id), isFalse);
  });

  test('deleting the session deletes its side chats', () async {
    final id = await start();
    repo.of(id).items.add(UserMessage('Why blue?'));
    await vm.delete();
    expect(sessions.byId(id), isNull);
  });
}
