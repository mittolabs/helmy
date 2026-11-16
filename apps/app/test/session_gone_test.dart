import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/claude/claude_reducer.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/echo_engine.dart';
import 'support/storage.dart';

/// A connection's session for a chat gone (deleted, or kept on another
/// computer): the chat starts a fresh one, handed the conversation, instead
/// of every message after failing in silence.
void main() {
  test("Claude Code's word for it is read as the session gone, not an interruption", () {
    final r = ClaudeReducer([]);
    r.apply({
      'type': 'result',
      'subtype': 'error_during_execution',
      'is_error': true,
      'session_id': 'old',
      'errors': ['No conversation found with session ID: old'],
    });
    final summary = r.items.whereType<TurnSummary>().single;
    expect((summary.ok, summary.error), (false, sessionGoneError));

    // A real interruption still reads as one.
    final stopped = ClaudeReducer([])
      ..apply({'type': 'result', 'subtype': 'error_during_execution', 'is_error': true});
    expect(stopped.items.whereType<TurnSummary>().single.ok, isTrue);
  });

  group('the chat', () {
    late Directory root;
    late SessionRepositoryLocal sessions;
    late ConversationRepositoryEngines repo;
    final stores = <StorageService>[];

    setUp(() async {
      root = await Directory.systemTemp.createTemp('gone');
      final storage = storageAt(root);
      stores.add(storage);
      sessions = SessionRepositoryLocal(storage);
    });
    tearDown(() async {
      repo.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (final s in stores) {
        await s.flush();
      }
      stores.clear();
      await root.delete(recursive: true);
    });

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 1000 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done(), isTrue);
    }

    test('starts a fresh session on the same connection and answers', () async {
      final engine = EchoEngine(['First answer.', 'Second answer.']);
      final storage = storageAt(root);
      stores.add(storage);
      final meter = UsageMeter();
      repo = ConversationRepositoryEngines(
        engines: EngineRegistry([engine]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      final s = (await sessions.create(cwd: root.path, title: 'Gone') as Ok).value as Session;
      await repo.send(s, 'Hello');
      await until(() => !repo.of(s.id).busy && engine.sent.length == 1);
      expect(sessions.byId(s.id)!.threads['claude']?.resumeId, isNotNull);

      engine.failCleanNext = sessionGoneError;
      await repo.send(sessions.byId(s.id)!, 'And now?');
      await until(() => !repo.of(s.id).busy && engine.launches.length == 2);

      // Started again, with no session to resume, and it answered.
      expect(engine.launches.last.resumeId, isNull);
      final items = repo.of(s.id).items;
      expect(items.whereType<AssistantText>().last.text, isNotEmpty);
      expect(items.whereType<TurnSummary>().last.ok, isTrue);
      expect(items.whereType<TurnSummary>().any((t) => t.error == sessionGoneError), isFalse);
      // It was handed the conversation so far.
      expect(engine.sent.length, greaterThanOrEqualTo(2));
    });
  });
}
