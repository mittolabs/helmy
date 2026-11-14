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
import 'package:helmy/utils/result.dart';

import 'support/echo_engine.dart';
import 'support/storage.dart';

/// A chat sent to from elsewhere (a phone, a schedule) before it was opened
/// here: it goes on from what was said, and nothing comes in twice.
void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('send-before-open'));
  tearDown(() => root.delete(recursive: true));

  ConversationRepositoryEngines make(StorageService storage, SessionRepositoryLocal sessions) {
    final meter = UsageMeter();
    return ConversationRepositoryEngines(
      engines: EngineRegistry([
        EchoEngine(['Done.']),
      ]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue);
  }

  test('a chat sent to before it is opened keeps what was said, once', () async {
    final storage = storageAt(root);
    final sessions = SessionRepositoryLocal(storage);
    final s = (await sessions.create(cwd: root.path, title: 'Pricing') as Ok).value as Session;
    var repo = make(storage, sessions);
    await repo.send(s, 'Fix the pricing page');
    await until(
      () => !repo.of(s.id).busy && repo.of(s.id).items.whereType<TurnSummary>().isNotEmpty,
    );
    repo.dispose();
    await storage.flush();

    // Helmy again, and the chat sent to from a phone before anyone opens it.
    repo = make(storage, sessions);
    await repo.send(s, 'Now the yearly toggle');
    await until(() => !repo.of(s.id).busy && repo.of(s.id).items.last is TurnSummary);
    await repo.load(s.id);

    expect(repo.of(s.id).items.whereType<UserMessage>().map((m) => m.text), [
      'Fix the pricing page',
      'Now the yearly toggle',
    ]);
    repo.dispose();
    await storage.flush();
  });
}
