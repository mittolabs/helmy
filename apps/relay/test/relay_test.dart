import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:helmy_relay/relay.dart';
import 'package:test/test.dart';

/// A computer on the relay, as Helmy is: proves its key, then answers each
/// phone's channel.
class FakeHost {
  FakeHost(this.ws, this.id, this._frames);
  final WebSocket ws;
  final String id;
  final StreamIterator<Object?> _frames;

  static Future<FakeHost> connect(
    int port, {
    SimpleKeyPair? key,
    bool lie = false,
  }) async {
    final pair = key ?? await Ed25519().newKeyPair();
    final ws = await WebSocket.connect('ws://127.0.0.1:$port/host');
    final frames = StreamIterator<Object?>(ws);
    await frames.moveNext();
    final nonce = '${jsonDecode('${frames.current}')['nonce']}';
    final sig = await Ed25519().sign(
      challengeText(lie ? 'other' : nonce),
      keyPair: pair,
    );
    final pub = (await pair.extractPublicKey()).bytes;
    ws.add(
      jsonEncode({
        'type': 'host',
        'pub': base64Url.encode(pub),
        'sig': base64Url.encode(sig.bytes),
      }),
    );
    if (!await frames.moveNext()) throw StateError('refused');
    final ready = jsonDecode('${frames.current}');
    return FakeHost(ws, '${ready['id']}', frames);
  }

  Future<Frame> next() async {
    if (!await _frames.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('closed');
    }
    return Frame.decode(_frames.current as List<int>)!;
  }

  void send(Frame f) => ws.add(f.encode());
}

void main() {
  late Relay relay;
  late int port;

  setUp(() async {
    relay = Relay(
      limits: const RelayLimits(phonesPerHost: 2, bytesPerDay: 1000),
    );
    await relay.start(address: InternetAddress.loopbackIPv4, port: 0);
    port = relay.port;
  });

  tearDown(() => relay.stop());

  Future<WebSocket> phone(String id, [String more = '']) =>
      WebSocket.connect('ws://127.0.0.1:$port/ws?h=$id$more');

  test('a computer proves its key, and its id is made from it', () async {
    final key = await Ed25519().newKeyPair();
    final host = await FakeHost.connect(port, key: key);
    expect(host.id, await hostId((await key.extractPublicKey()).bytes));
    expect(host.id, hasLength(22));
    expect(relay.hosts, 1);
  });

  test('a computer that signs the wrong thing is turned away', () async {
    await expectLater(FakeHost.connect(port, lie: true), throwsStateError);
    expect(relay.hosts, 0);
  });

  test('a phone and the computer talk through a channel, both ways', () async {
    final host = await FakeHost.connect(port);
    final p = await phone(host.id, '&d=tito&x=1');
    final heard = StreamIterator<Object?>(p);

    final open = await host.next();
    expect(open.kind, FrameKind.open);
    expect(open.query, {
      'd': 'tito',
      'x': '1',
    }, reason: 'the query, without the computer id');

    p.add('sealed hello');
    final hello = await host.next();
    expect(
      (hello.kind, hello.channel, hello.text),
      (FrameKind.text, open.channel, 'sealed hello'),
    );

    host.send(Frame.text(open.channel, 'sealed state'));
    await heard.moveNext();
    expect(heard.current, 'sealed state');

    p.add([1, 2, 3]);
    final bin = await host.next();
    expect(bin.kind, FrameKind.binary);
    expect(bin.payload, [1, 2, 3]);

    host.send(Frame.close(open.channel, 4001, 'unpaired'));
    expect(await heard.moveNext(), isFalse);
    expect((p.closeCode, p.closeReason), (4001, 'unpaired'));
  });

  test('a phone closing tells the computer', () async {
    final host = await FakeHost.connect(port);
    final p = await phone(host.id);
    final open = await host.next();
    await p.close();
    final closed = await host.next();
    expect((closed.kind, closed.channel), (FrameKind.close, open.channel));
  });

  test('a phone for a computer not connected hears it is offline', () async {
    final p = await phone('nobody');
    await p.drain<void>();
    expect(p.closeCode, RelayClose.offline);
  });

  test('a second phone past the limit is told the computer is busy', () async {
    final host = await FakeHost.connect(port);
    await phone(host.id);
    await phone(host.id);
    final third = await phone(host.id);
    await third.drain<void>();
    expect(third.closeCode, RelayClose.busy);
  });

  test('more than a day\'s share is cut off', () async {
    final host = await FakeHost.connect(port);
    final p = await phone(host.id);
    final open = await host.next();
    host.send(Frame(FrameKind.binary, open.channel, Uint8List(2000)));
    await p.drain<void>();
    expect(p.closeCode, RelayClose.overQuota);
  });

  test(
    'the same computer connecting again replaces the first, and its phones go',
    () async {
      final key = await Ed25519().newKeyPair();
      final first = await FakeHost.connect(port, key: key);
      final p = await phone(first.id);
      await first.next();
      final second = await FakeHost.connect(port, key: key);
      expect(second.id, first.id);
      await p.drain<void>();
      expect(p.closeCode, RelayClose.offline);
      expect(relay.hosts, 1);
      final again = await phone(second.id);
      expect((await second.next()).kind, FrameKind.open);
      await again.close();
    },
  );

  test('the phone page: its files, and itself for any route', () async {
    final dir = await Directory.systemTemp.createTemp('page');
    await File('${dir.path}/index.html').writeAsString('<p>helmy</p>');
    await File('${dir.path}/main.dart.js').writeAsString('main()');
    final served = Relay(page: dir);
    await served.start(address: InternetAddress.loopbackIPv4, port: 0);
    Future<(int, String)> get(String path) async {
      final res = await (await HttpClient().get(
        '127.0.0.1',
        served.port,
        path,
      )).close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    }

    expect(await get('/'), (200, '<p>helmy</p>'));
    expect(await get('/main.dart.js'), (200, 'main()'));
    expect(await get('/chats/1'), (
      200,
      '<p>helmy</p>',
    ), reason: 'a route is the page');
    expect((await get('/missing.js')).$1, 404);
    expect((await get('/%2E%2E/relay_test.dart')).$1, 404);
    await served.stop();
  });

  test('health', () async {
    final res = await (await HttpClient().get(
      '127.0.0.1',
      port,
      '/healthz',
    )).close();
    expect(res.statusCode, 200);
  });
}
