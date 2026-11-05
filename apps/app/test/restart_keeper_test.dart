import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/restart_keeper.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

/// Chats at work when Helmy closed carry on when it opens again.
void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('restart'));
  tearDown(() => deleteFolder(root));

  test('what was working is written down, and carried on at the next start', () async {
    final storage = storageAt(root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    ConversationRepositoryEngines repo() => ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final first = repo();
    final a = (await sessions.create(cwd: root.path, title: 'Budget') as Ok).value as Session;
    final b = (await sessions.create(cwd: root.path, title: 'Trip') as Ok).value as Session;
    final keeper = RestartKeeper(storage, sessions, first);
    expect(await keeper.start(), isEmpty, reason: 'nothing was working before');
    first.of(a.id).busy = true;
    first.notifyListeners();
    await storage.flush();
    keeper.dispose();
    first.dispose();

    // Opened again: Budget was at work, Trip was not.
    final second = repo();
    final again = RestartKeeper(storage, sessions, second);
    expect(await again.start(), [a.id]);
    final said = second.of(a.id).items.whereType<UserMessage>().last;
    expect(said.text, RestartKeeper.carryOn);
    expect(said.from, 'Helmy, after a restart');
    expect(second.of(b.id).items.whereType<UserMessage>(), isEmpty);

    // Turned off: not carried on.
    second.of(a.id).busy = true;
    second.notifyListeners();
    await storage.flush();
    again.dispose();
    final third = RestartKeeper(storage, sessions, repo(), enabled: () => false);
    expect(await third.start(), isEmpty);
    third.dispose();
  });
}
