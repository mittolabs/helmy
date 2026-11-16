import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/remote/remote_crypto.dart';
import 'package:helmy/data/services/remote/remote_host.dart';
import 'package:helmy/data/services/remote/remote_link.dart';
import 'package:helmy/data/services/remote/remote_server.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy_relay/relay.dart';

import '../testing/fake_repositories.dart';
import 'support/storage.dart';

/// Helmy Connect: a code used once, for a key never in it; and a phone
/// reaching the computer through the relay, sealed end to end.
void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ChatRepository chats;
  late ConversationRepositoryEngines repo;
  late RemoteServer server;
  const port = 47961;

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 330 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('connect');
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
  });

  tearDown(() async {
    await server.stop();
    repo.dispose();
    chats.dispose();
    await deleteFolder(root);
  });

  group('the exchange', () {
    final offer = Pairing(
      hosts: const ['10.0.0.2'],
      port: port,
      key: '',
      secret: Pairing.newKey(),
      name: 'Studio',
      device: 'tito',
      relay: 'abc',
    );

    test('a code carries a secret, not a key, and reads back the same', () {
      expect(offer.link, startsWith('helmy-pair:v3?'));
      expect(offer.link, isNot(contains('k=')));
      final back = Pairing.parse(offer.link)!;
      expect(
        (back.isOffer, back.secret, back.device, back.relay),
        (true, offer.secret, 'tito', 'abc'),
      );
      expect(offer.webLink, startsWith('https://connect.helmy.ke/#helmy-pair:v3?'));
      expect(Pairing.parse(offer.webLink)?.secret, offer.secret);
      expect(
        Pairing.parse(offer.link.replaceFirst('&d=tito', '')),
        isNull,
        reason: 'no phone, no code',
      );
    });

    test('both sides come to the same key, and the code cannot be faked', () async {
      final started = await PairingExchange.start(offer);
      final answer = await PairingExchange.answer(offer.secret!, 'tito', started.message);
      expect(answer, isNotNull);
      final key = await PairingExchange.finish(offer, started, answer!.message);
      expect(key, answer.key);
      expect(key, isNot(offer.secret));

      // Someone without the secret cannot pass for the phone, or the computer.
      expect(await PairingExchange.answer(Pairing.newKey(), 'tito', started.message), isNull);
      final impostor =
          await PairingExchange.answer(Pairing.newKey(), 'tito', started.message) ??
          (message: {'type': 'exchanged', 'pub': answer.message['pub'], 'proof': 'AAAA'}, key: '');
      expect(await PairingExchange.finish(offer, started, impostor.message), isNull);
    });
  });

  test('a code works once: the next use is refused, and a new code is shown', () async {
    final settings = FakeSettingsRepository(
      const AppSettings(remoteOn: true, remoteAnywhere: false),
    );
    final host = RemoteHost(server, settings);
    addTearDown(host.dispose);
    await until(() => host.pairing?.secret != null);
    final code = host.pairing!;
    expect(code.relay, isNull, reason: 'From anywhere is off');
    final local = Pairing.parse(code.link.replaceFirst(RegExp(r'h=[^&]*'), 'h=127.0.0.1'))!;

    final first = await RemoteLink.exchange(local);
    expect(first.trouble, isNull);
    final paired = first.pairing!;
    expect((paired.isOffer, paired.key.length), (false, 43));
    expect(settings.settings.phones.where((p) => p.id == code.device).single.key, paired.key);

    final again = await RemoteLink.exchange(local);
    expect(again.pairing, isNull);
    expect(again.trouble, contains('already used'));

    // The secret is no key: a phone trying it as one is turned away.
    final pretend = RemoteLink(local.exchanged(local.secret!));
    addTearDown(pretend.dispose);
    await pretend.connect();
    await until(() => pretend.state == LinkState.unreachable);
    expect(pretend.state, LinkState.unreachable);

    final link = RemoteLink(paired);
    addTearDown(link.dispose);
    await link.connect();
    await until(() => link.state == LinkState.connected);
    expect(link.state, LinkState.connected);
    await until(() => host.pairing?.device != code.device);
    expect(host.pairing!.device, isNot(code.device), reason: 'the next phone gets its own');
  });

  test('a code shown too long is replaced, and one from before is too', () async {
    final settings = FakeSettingsRepository(
      AppSettings(
        remoteOn: true,
        remoteAnywhere: false,
        phones: [
          PairedPhone(
            id: 'old',
            key: '',
            secret: Pairing.newKey(),
            madeAt: DateTime.now().subtract(const Duration(minutes: 20)),
          ),
          PairedPhone(id: 'keyed', key: Pairing.newKey()),
        ],
      ),
    );
    final host = RemoteHost(server, settings);
    addTearDown(host.dispose);
    await until(() => host.pairing?.secret != null);
    expect(host.pairing!.device, isNot(anyOf('old', 'keyed')));
    expect(settings.settings.phones.map((p) => p.id), isNot(contains('old')));
    expect(settings.settings.phones.map((p) => p.id), isNot(contains('keyed')));
  });

  test('through the relay: paired and connected with no address on the network', () async {
    final relay = Relay();
    await relay.start(address: InternetAddress.loopbackIPv4, port: 0);
    addTearDown(relay.stop);
    final settings = FakeSettingsRepository(const AppSettings(remoteOn: true));
    final host = RemoteHost(server, settings, relayUrl: 'ws://127.0.0.1:${relay.port}');
    addTearDown(host.dispose);
    await until(() => host.relay?.connected == true && host.pairing?.relay != null);
    expect(host.relay!.connected, isTrue);
    final code = host.pairing!;
    expect(code.relay, host.relay!.id);
    expect(code.webLink, startsWith('http://127.0.0.1:${relay.port}/#helmy-pair:v3?'));

    // Only the relay: the network's addresses left out.
    final away = Pairing.parse(code.link.replaceFirst(RegExp(r'h=[^&]*'), 'h=192.0.2.1'))!;
    final used = await RemoteLink.exchange(away);
    expect(used.trouble, isNull);
    final link = RemoteLink(used.pairing!);
    addTearDown(link.dispose);
    await link.connect();
    await until(() => link.state == LinkState.connected);
    expect(link.state, LinkState.connected);
    await until(() => host.phones.isNotEmpty);
    expect(host.isConnected(code.device!), isTrue);

    // Unpaired on the computer: turned away through the relay too.
    await host.unpair(code.device!);
    await until(() => link.state == LinkState.unreachable);
    expect(link.trouble, isNotNull);
  });

  test('the computer not on the relay: the phone hears it is not connected', () async {
    final relay = Relay();
    await relay.start(address: InternetAddress.loopbackIPv4, port: 0);
    addTearDown(relay.stop);
    final offer = Pairing(
      hosts: const [],
      port: port,
      key: '',
      secret: Pairing.newKey(),
      name: 'Studio',
      device: 'tito',
      relay: 'nobody',
      relayUrl: 'ws://127.0.0.1:${relay.port}',
    );
    final used = await RemoteLink.exchange(offer);
    expect(used.pairing, isNull);
    expect(used.trouble, contains("isn't connected to Helmy Connect"));
  });
}
