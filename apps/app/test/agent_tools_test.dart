import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/agent_tools.dart';
import 'package:helmy/data/services/approvals.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/echo_engine.dart';
import 'support/storage.dart';

/// Background agents: work a chat hands off goes on beside it, its answer
/// comes back to the chat as Helmy's message, never as the person's.
void main() {
  late Directory root;
  late StorageService storage;
  late SessionRepositoryLocal sessions;
  late ConversationRepositoryEngines repo;
  late AgentTools tools;
  late EchoEngine claude, codex;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agents');
    storage = storageAt(root);
    sessions = SessionRepositoryLocal(storage);
    claude = EchoEngine(['Chat answer.', 'Carried on with it.']);
    codex = EchoEngine(['The Android build passes.'], id: 'codex');
    final meter = UsageMeter();
    repo = ConversationRepositoryEngines(
      engines: EngineRegistry([claude, codex]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    tools = AgentTools(sessions: sessions, conversations: repo);
  });
  tearDown(() async {
    // What the chat was still answering (an agent's report) lands first.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    tools.dispose();
    repo.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await storage.flush();
    await root.delete(recursive: true);
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue);
  }

  String text(Map<String, Object?> r) => ((r['content'] as List).single as Map)['text'] as String;

  Future<Session> chat() async {
    final s = (await sessions.create(cwd: root.path, title: 'Dust Run') as Ok).value as Session;
    await repo.send(s, 'Build the game');
    await until(() => !repo.of(s.id).busy);
    return sessions.byId(s.id)!;
  }

  test('one started works beside the chat, and its answer comes back as Helmy\'s', () async {
    final s = await chat();
    await sessions.save(s.copyWith(away: true));
    final r = await tools.call('agent_start', {
      'title': 'Check Android',
      'task': 'Build the Android app and say if it passes.',
      'second_opinion': true,
    }, s.id);
    expect(r['isError'], isFalse, reason: text(r));

    final agent = tools.agentsOf(s.id).single;
    expect(agent.agent, isTrue);
    expect(agent.sideOf, s.id);
    expect(agent.away, isTrue, reason: 'it works as its chat does');
    expect(agent.avoid, s.lastEngineId, reason: 'a second opinion starts elsewhere');
    // Its task is Helmy's, not the person asking.
    final task = repo.of(agent.id).items.whereType<UserMessage>().first;
    expect(Approvals.byThePerson(task), isFalse);

    // It finishes: the chat hears of it, from Helmy, and carries on.
    await until(() => repo.of(s.id).items.whereType<UserMessage>().length == 2);
    final report = repo.of(s.id).items.whereType<UserMessage>().last;
    expect(report.text, contains('The Android build passes.'));
    expect(report.from, AgentTools.fromAgent('Check Android'));
    expect(Approvals.byThePerson(report), isFalse);
    expect(sessions.byId(agent.id)!.lastEngineId, 'codex', reason: 'on another connection');

    final status = await tools.call('agent_status', {'id': agent.id}, s.id);
    expect(text(status), allOf(contains('is done'), contains('The Android build passes.')));
  });

  test('an agent starts none of its own, and a chat runs a few at once', () async {
    final s = await chat();
    final first = await tools.call('agent_start', {'title': 'A', 'task': 'Do A.'}, s.id);
    final agent = tools.agentsOf(s.id).single;
    expect(first['isError'], isFalse);
    final nested = await tools.call('agent_start', {'title': 'B', 'task': 'Do B.'}, agent.id);
    expect(nested['isError'], isTrue);
    expect(text(nested), contains('background agent yourself'));
    expect(text(await tools.call('agent_status', {}, s.id)), contains('"A" (id ${agent.id})'));
    await until(() => repo.of(s.id).items.whereType<UserMessage>().length == 2);
  });

  test("a chat's agents are not its side chats, and leave the list alone", () async {
    final s = await chat();
    await tools.call('agent_start', {'title': 'A', 'task': 'Do A.'}, s.id);
    final listed = sessions.sessions.where((x) => x.sideOf == null).map((x) => x.id);
    expect(listed, [s.id]);
    await until(() => repo.of(s.id).items.whereType<UserMessage>().length == 2);
  });
}
