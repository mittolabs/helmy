import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';

import 'support/storage.dart';

void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ChatRepository chats;
  late SidebarViewModel vm;
  late FakeSettingsRepository settings;

  Future<Session> thread(String title, {String? chatId}) async =>
      (await sessions.create(cwd: '/w', title: title, chatId: chatId) as Ok).value as Session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sidebar');
    final storage = storageAt(root);
    sessions = SessionRepositoryLocal(storage);
    chats = ChatRepository(storage, sessions);
    await chats.load();
    final meter = UsageMeter();
    settings = FakeSettingsRepository();
    vm = SidebarViewModel(
      sessions: sessions,
      conversations: ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      ),
      settings: settings,
      chats: chats,
    );
  });
  tearDown(() async {
    vm.dispose();
    chats.dispose();
    await root.delete(recursive: true);
  });

  test('every row is one conversation: one put in a chat with another gets its own', () async {
    final budget = await thread('November budget');
    final trip = await thread('Lisbon trip');
    final car = await thread('Car loan', chatId: sessions.byId(budget.id)!.chatId);
    final entries = vm.entriesOf(vm.shown);
    expect(entries.length, 3);
    for (final e in entries) {
      expect(e.threads, hasLength(1), reason: 'a chat is one conversation');
    }
    expect(sessions.byId(car.id)!.chatId, isNot(sessions.byId(budget.id)!.chatId));
    expect(vm.titleOf(entries.firstWhere((e) => e.threads.single.id == trip.id)), 'Lisbon trip');
  });
}
