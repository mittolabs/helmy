import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/approvals.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/goal.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/echo_engine.dart';
import 'support/storage.dart';

/// A chat's standing goal: Helmy keeps the agent going until it says the goal is met.
void main() {
  test('what /goal asks', () {
    expect(goalCommand('/goal'), isA<GoalShow>());
    expect(goalCommand(' /goal pause '), isA<GoalPause>());
    expect(goalCommand('/goal resume'), isA<GoalResume>());
    expect(goalCommand('/goal clear'), isA<GoalClear>());
    expect((goalCommand('/goal Ship the migration') as GoalSet).objective, 'Ship the migration');
    expect(goalCommand('/goals are nice'), isNull);
    expect(goalCommand('the /goal is'), isNull);
  });

  test('the marker says met, and leaves the answer', () {
    expect(goalMetIn('All checked.\nHELMY_GOAL_MET'), isTrue);
    expect(goalMetIn('I will write HELMY_GOAL_MET when done.'), isFalse);
    expect(withoutGoalMarker('All checked.\n\nHELMY_GOAL_MET\n'), 'All checked.');
  });

  group('in a chat', () {
    late Directory root;
    late StorageService storage;
    late SessionRepositoryLocal sessions;
    late ConversationRepositoryEngines repo;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('goal');
      storage = storageAt(root);
      sessions = SessionRepositoryLocal(storage);
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      repo.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await storage.flush();
      await root.delete(recursive: true);
    });

    ConversationRepositoryEngines make(EchoEngine e) {
      final meter = UsageMeter();
      return ConversationRepositoryEngines(
        engines: EngineRegistry([e]),
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

    test('it goes on by itself until the agent says the goal is met', () async {
      final engine = EchoEngine([
        'Backend done.',
        'Screens done.',
        'All checked and passing.\nHELMY_GOAL_MET',
      ]);
      repo = make(engine);
      var s = (await sessions.create(cwd: root.path, title: 'Spotly') as Ok).value as Session;
      await sessions.save(s.copyWith(goal: 'Ship the Spotly migration'));
      s = sessions.byId(s.id)!;
      await repo.send(s, 'Goal: Ship the Spotly migration');
      await until(() => sessions.byId(s.id)!.goal == null && !repo.of(s.id).busy);

      expect(engine.sent, hasLength(3));
      final asked = repo.of(s.id).items.whereType<UserMessage>().toList();
      expect(asked.skip(1).every((m) => m.from == goalFrom), isTrue);
      expect(asked.skip(1).every((m) => !Approvals.byThePerson(m)), isTrue);
      expect(repo.of(s.id).items.whereType<AssistantText>().last.text, 'All checked and passing.');
      expect(
        repo.of(s.id).items.whereType<Notice>().last.text,
        'Goal met: Ship the Spotly migration',
      );
    });

    test('a paused goal is kept, and nothing goes on by itself', () async {
      final engine = EchoEngine(['Backend done.']);
      repo = make(engine);
      var s = (await sessions.create(cwd: root.path, title: 'Spotly') as Ok).value as Session;
      await sessions.save(s.copyWith(goal: 'Ship it', goalPaused: true));
      s = sessions.byId(s.id)!;
      await repo.send(s, 'Do the backend');
      await until(() => !repo.of(s.id).busy && engine.sent.length == 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.sent, hasLength(1));
      expect(sessions.byId(s.id)!.goal, 'Ship it');
    });
  });
}
