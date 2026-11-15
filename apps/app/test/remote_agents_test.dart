import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/agent_tools.dart';
import 'package:helmy/data/services/approvals.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/remote/remote_crypto.dart';
import 'package:helmy/data/services/remote/remote_server.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/echo_engine.dart';
import 'support/storage.dart';

/// A background agent on another of the person's computers: started there over the
/// paired link, as Helmy's words; its answer comes back to the chat here.
void main() {
  late Directory root;
  late List<StorageService> stores;
  late ConversationRepositoryEngines here, there;
  late SessionRepositoryLocal hereSessions, thereSessions;
  late RemoteServer server;
  late AgentTools tools;
  final key = Pairing.newKey();
  const port = 47941;

  ConversationRepositoryEngines repo(
    StorageService s,
    SessionRepositoryLocal sessions,
    EchoEngine e,
  ) {
    final meter = UsageMeter();
    return ConversationRepositoryEngines(
      engines: EngineRegistry([e]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: s,
      sessions: sessions,
    );
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 1500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('remote-agents');
    stores = [
      storageAt(Directory('${root.path}/here')),
      storageAt(Directory('${root.path}/there')),
    ];
    hereSessions = SessionRepositoryLocal(stores[0]);
    thereSessions = SessionRepositoryLocal(stores[1]);
    here = repo(stores[0], hereSessions, EchoEngine(['Asked Studio to check it.', 'Noted.']));
    there = repo(stores[1], thereSessions, EchoEngine(['The Windows build passes.']));
    final chats = ChatRepository(stores[1], thereSessions);
    await chats.load();
    // Studio has worked somewhere before: a new chat there starts in that folder.
    await thereSessions.create(cwd: '${root.path}/studio-project', title: 'Earlier');
    server = RemoteServer(sessions: thereSessions, conversations: there, chats: chats, port: port);
    await server.start(key);
    tools = AgentTools(
      sessions: hereSessions,
      conversations: here,
      computers: () => [
        Pairing(hosts: const ['127.0.0.1'], port: port, key: key, name: 'Studio'),
      ],
    );
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    tools.dispose();
    await server.stop();
    here.dispose();
    there.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (final s in stores) {
      await s.flush();
    }
    await root.delete(recursive: true);
  });

  test('started on Studio, as Helmy; its answer comes back here', () async {
    final s = (await hereSessions.create(cwd: root.path, title: 'Release') as Ok).value as Session;
    await here.send(s, 'Check Windows on Studio');
    await until(() => !here.of(s.id).busy);

    final r = await tools.call('agent_start', {
      'title': 'Windows build',
      'task': 'Build the Windows app and say if it passes.',
      'computer': 'studio',
    }, s.id);
    expect(r['isError'], isFalse, reason: '${r['content']}');

    // On Studio: a chat with the task, as Helmy's words, never the person's.
    await until(() => thereSessions.sessions.length == 2);
    final made = thereSessions.sessions.firstWhere((x) => x.title != 'Earlier');
    await until(() => there.of(made.id).items.whereType<UserMessage>().isNotEmpty);
    final task = there.of(made.id).items.whereType<UserMessage>().first;
    expect(task.text, 'Build the Windows app and say if it passes.');
    expect(Approvals.byThePerson(task), isFalse);

    // Its answer, back here.
    await until(() => here.of(s.id).items.whereType<UserMessage>().length == 2);
    final report = here.of(s.id).items.whereType<UserMessage>().last;
    expect(report.text, contains('on Studio'));
    expect(report.text, contains('The Windows build passes.'));
    expect(report.from, AgentTools.fromAgent('Windows build'));

    final status = await tools.call('agent_status', {}, s.id);
    final said = ((status['content'] as List).single as Map)['text'] as String;
    expect(said, contains('"Windows build" on Studio'));
    expect(said, contains('Other computers to start one on: Studio.'));
  });

  test('a computer not paired, by name, is said so', () async {
    final s = (await hereSessions.create(cwd: root.path, title: 'Release') as Ok).value as Session;
    final r = await tools.call('agent_start', {
      'title': 'X',
      'task': 'Do X.',
      'computer': 'Laptop',
    }, s.id);
    expect(r['isError'], isTrue);
    expect('${r['content']}', contains('Paired: Studio'));
  });
}
