import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/remote/remote_crypto.dart';
import 'package:helmy/data/services/remote/remote_link.dart';
import 'package:helmy/data/services/remote/remote_server.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

/// A phone and the Mac, over a sealed WebSocket: the list, a conversation
/// as it goes, sending; and a phone without the key gets nothing.
void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ChatRepository chats;
  late ConversationRepositoryEngines repo;
  late RemoteServer server;
  final key = Pairing.newKey();
  const port = 47923;

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('remote');
    final storage = storageAt(root);
    sessions = SessionRepositoryLocal(storage);
    chats = ChatRepository(storage, sessions);
    await chats.load();
    final meter = UsageMeter();
    repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    server = RemoteServer(sessions: sessions, conversations: repo, chats: chats, port: port);
    await server.start(key);
  });
  tearDown(() async {
    await server.stop();
    repo.dispose();
    chats.dispose();
    await deleteFolder(root);
  });

  test('a pairing goes into a link and back out unchanged; anything else is no pairing', () {
    final p = Pairing(
      hosts: const ['192.168.1.20', '100.64.0.7'],
      port: port,
      key: key,
      name: 'Studio',
    );
    final back = Pairing.parse(p.link)!;
    expect(back.hosts, p.hosts);
    expect((back.port, back.key, back.name), (port, key, 'Studio'));
    expect(Pairing.parse('https://example.com'), isNull);
    expect(Pairing.parse('helmy-pair:v1?h=1.2.3.4&p=1&k=short'), isNull);
  });

  test('a paired phone sees the chats, follows a conversation and sends into it', () async {
    final s = (await sessions.create(cwd: root.path, title: 'Budget') as Ok).value as Session;
    repo.of(s.id)
      ..loaded = true
      ..items.addAll([UserMessage('How much is left?'), AssistantText('a', 'About \$420.')]);
    final link = RemoteLink(
      Pairing(hosts: const ['127.0.0.1'], port: port, key: key, name: 'Studio'),
    );
    addTearDown(link.dispose);
    await link.connect();
    await until(() => link.chats.isNotEmpty);
    expect(link.state, LinkState.connected);
    final row = link.chats.expand((c) => c.threads).singleWhere((t) => t.id == s.id);
    expect((row.title, row.last), ('Budget', 'About \$420.'));

    await link.open(s.id);
    await until(() => link.of(s.id).items.length >= 2);
    expect((link.of(s.id).items.last as AssistantText).text, 'About \$420.');

    await link.send(s.id, 'And next month?');
    await until(() => link.of(s.id).items.whereType<UserMessage>().length >= 2);
    expect(repo.of(s.id).items.whereType<UserMessage>().last.text, 'And next month?');
    expect(link.of(s.id).items.whereType<UserMessage>().last.text, 'And next month?');
  });

  test('a phone without the key is closed on, and told nothing', () async {
    final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    final got = <Object?>[];
    final done = Completer<void>();
    ws.listen(got.add, onDone: done.complete);
    ws.add(await Sealer(Pairing.newKey()).seal({'type': 'hello'}));
    await done.future.timeout(const Duration(seconds: 3));
    expect(got, isEmpty);
    expect(ws.closeCode, WebSocketStatus.policyViolation);
    expect(server.connected, 0);
  });
}
