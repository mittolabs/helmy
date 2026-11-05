import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/remote/remote_repositories.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/remote/remote_crypto.dart';
import 'package:helmy/data/services/remote/remote_link.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/data/services/remote/remote_host.dart';
import 'package:helmy/data/services/remote/remote_server.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';
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
    for (var i = 0; i < 330 && !done(); i++) {
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

  test('phones with keys of their own: told apart, and one unpaired alone', () async {
    final keys = {'tito': Pairing.newKey(), 'sam': Pairing.newKey()};
    final hellos = <String, String>{};
    server.keyOf = (d) => keys[d];
    server.onHello = (d, name) => hellos[d] = name;
    final mine = Pairing(
      hosts: const ['127.0.0.1'],
      port: port,
      key: keys['tito']!,
      name: 'Studio',
      device: 'tito',
    );
    expect(Pairing.parse(mine.link)?.device, 'tito', reason: 'the code carries which phone');
    RemoteLink linkFor(String d) => RemoteLink(
      Pairing(hosts: const ['127.0.0.1'], port: port, key: keys[d]!, name: 'Studio', device: d),
    );
    final a = linkFor('tito'), b = linkFor('sam');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.connect();
    await b.connect();
    await until(() => hellos.length == 2);
    expect(hellos.keys, unorderedEquals(['tito', 'sam']));
    expect(hellos['tito'], phoneName());
    expect(server.connectedDevices, {'tito', 'sam'});

    // Unpaired: its key goes and it is dropped; the other stays.
    keys.remove('sam');
    await server.drop('sam');
    await until(() => b.state == LinkState.unreachable);
    expect(server.connectedDevices, {'tito'});
    expect(a.state, LinkState.connected);

    // Another phone's key with its id: turned away.
    final wrong = RemoteLink(
      Pairing(
        hosts: const ['127.0.0.1'],
        port: port,
        key: Pairing.newKey(),
        name: 'S',
        device: 'tito',
      ),
    );
    addTearDown(wrong.dispose);
    await wrong.connect();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(wrong.state, isNot(LinkState.connected));
  });

  test('pairing on the Mac: a code per phone, named when it pairs, unpaired alone', () async {
    await server.stop();
    final settings = FakeSettingsRepository(const AppSettings(remoteOn: true));
    final host = RemoteHost(server, settings);
    addTearDown(host.dispose);
    await until(() => host.pairing?.device != null);
    final first = host.pairing!;
    expect(host.phones, isEmpty, reason: 'shown, not yet scanned');
    final link = RemoteLink(
      Pairing(
        hosts: const ['127.0.0.1'],
        port: port,
        key: first.key,
        name: 'Studio',
        device: first.device,
      ),
    );
    addTearDown(link.dispose);
    await link.connect();
    await until(() => host.phones.isNotEmpty);
    expect(host.phones.single.name, phoneName());
    expect(host.isConnected(first.device!), isTrue);
    // Scanned: the next phone gets a code of its own.
    await until(() => host.pairing?.device != first.device);
    expect(host.pairing!.device, isNot(first.device));

    await host.unpair(first.device!);
    expect(host.phones, isEmpty);
    await until(() => link.state == LinkState.unreachable);
    expect(link.state, LinkState.unreachable);
  });

  test('starting changes no settings while it is being made', () async {
    await server.stop();
    // No code waiting: one is made and saved, but only once the host exists,
    // since a save in the middle of building stopped the app opening.
    final settings = FakeSettingsRepository(const AppSettings(remoteOn: true));
    var told = 0;
    settings.addListener(() => told++);
    final host = RemoteHost(server, settings);
    addTearDown(host.dispose);
    expect(told, 0);
    await until(() => host.pairing?.device != null);
    expect(told, greaterThan(0));
  });

  test('a picture the chat shows comes to the phone; nothing else on the Mac does', () async {
    final s = (await sessions.create(cwd: root.path, title: 'Headshot') as Ok).value as Session;
    final picture = File('${root.path}/headshot.png')..writeAsBytesSync([137, 80, 78, 71, 1, 2, 3]);
    final secret = File('${root.path}/secret.txt')..writeAsStringSync('not for phones');
    repo.of(s.id)
      ..loaded = true
      ..items.addAll([
        UserMessage('make a headshot'),
        AssistantText('a', 'Ready.\n\n![Your headshot](${picture.path})'),
      ]);
    final link = RemoteLink(
      Pairing(hosts: const ['127.0.0.1'], port: port, key: key, name: 'Studio'),
    );
    addTearDown(link.dispose);
    await link.connect();
    await until(() => link.state == LinkState.connected);
    expect(await link.file(s.id, picture.path), [137, 80, 78, 71, 1, 2, 3]);
    expect(await link.file(s.id, secret.path), isNull);

    // The phone's chat shows its own copy, fetched by itself.
    final conversations = RemoteConversations(link);
    addTearDown(conversations.dispose);
    await conversations.load(s.id);
    String shown() =>
        (conversations.of(s.id).items.whereType<AssistantText>().firstOrNull)?.text ?? '';
    await until(() => shown().isNotEmpty && !shown().contains(root.path));
    expect(shown(), isNot(contains(root.path)));
    final local = RegExp(r'\((/[^)]+)\)').firstMatch(shown())![1]!;
    expect(File(local).readAsBytesSync(), [137, 80, 78, 71, 1, 2, 3]);
  });
}
