import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';

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
    final storage = StorageService(root: () async => root);
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

  test("a chat's threads show as one row, where its newest was; a lone thread as itself", () async {
    final budget = await thread('November budget');
    final trip = await thread('Lisbon trip');
    final car = await thread('Car loan', chatId: sessions.byId(budget.id)!.chatId);
    final entries = vm.entriesOf(vm.shown);
    expect(entries.length, 2);
    expect(
      entries.first.chat?.id,
      sessions.byId(budget.id)!.chatId,
      reason: 'its newest thread is the newest',
    );
    expect([for (final t in entries.first.threads) t.id], [car.id, budget.id]);
    expect((entries.last.chat, entries.last.threads.single.id), (null, trip.id));
  });

  test('earlier threads that belong together are suggested, moved only when chosen', () async {
    final money = await thread('Monthly budget for November');
    await thread('Paying off the car loan', chatId: sessions.byId(money.id)!.chatId);
    final loose = await thread('Car loan and budget for December');
    await thread('A haiku about rain');
    final found = vm.suggestions;
    expect([for (final f in found) f.thread.id], [loose.id]);
    expect(found.single.into.id, sessions.byId(money.id)!.chatId);

    await vm.applySuggestions(found);
    expect(sessions.byId(loose.id)!.chatId, sessions.byId(money.id)!.chatId);
    expect(settings.settings.groupingReviewed, isTrue);
    expect(vm.suggestions, isEmpty, reason: 'offered once');
  });

  test('dismissed, nothing moves and it is not offered again', () async {
    final money = await thread('Monthly budget for November');
    await thread('Paying off the car loan', chatId: sessions.byId(money.id)!.chatId);
    final loose = await thread('Car loan and budget for December');
    final before = sessions.byId(loose.id)!.chatId;
    await vm.applySuggestions(const []);
    expect(sessions.byId(loose.id)!.chatId, before);
    expect(vm.suggestions, isEmpty);
  });
}
