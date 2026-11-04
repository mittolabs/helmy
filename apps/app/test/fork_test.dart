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
import 'package:helmy/utils/result.dart';

void main() {
  test('a fork takes the conversation up to that answer, and goes its own way', () async {
    final root = await Directory.systemTemp.createTemp('fork');
    addTearDown(() => root.delete(recursive: true));
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
    await sessions.save(s.copyWith(title: 'Plan the launch'));
    repo.of(s.id)
      ..loaded = true
      ..items.addAll([
        UserMessage('first'),
        AssistantText('a', 'one'),
        TurnSummary(ok: true),
        UserMessage('second'),
        AssistantText('b', 'two'),
        TurnSummary(ok: true),
      ]);
    final vm = ChatViewModel(sessionId: s.id, sessions: sessions, conversations: repo);
    final id = await vm.fork(2);
    expect(id, isNotNull);
    final fork = sessions.byId(id!)!;
    expect(fork.title, 'Plan the launch fork');
    expect(fork.cwd, root.path);
    final items = repo.of(id).items;
    expect(items.whereType<UserMessage>().map((m) => m.text), ['first']);
    expect((items.last as Notice).text, 'Forked from "Plan the launch"');

    // They go their own ways: a change to one leaves the other.
    (items.first as UserMessage).text;
    repo.of(id).items.add(UserMessage('only in the fork'));
    expect(repo.of(s.id).items.whereType<UserMessage>(), hasLength(2));
    vm.dispose();
    repo.dispose();
    await storage.flush();
  });
}
