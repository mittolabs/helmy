import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/remote/remote_crypto.dart';
import 'package:helmy/data/services/remote/remote_server.dart';

import 'support/storage.dart';

/// Helmy in a phone's browser: the code's link opens a page this computer
/// serves, and carries the pairing where the browser keeps it to itself.
void main() {
  /// A pack as tool/remote.mjs makes one.
  Uint8List pack(Map<String, String> files) {
    final index = <String, List<int>>{};
    final body = BytesBuilder();
    for (final e in files.entries) {
      final gz = gzip.encode(utf8.encode(e.value));
      index[e.key] = [body.length, gz.length];
      body.add(gz);
    }
    final head = utf8.encode(jsonEncode(index));
    return Uint8List.fromList([
      ...(ByteData(4)..setUint32(0, head.length)).buffer.asUint8List(),
      ...head,
      ...body.takeBytes(),
    ]);
  }

  test("the code's link opens in a browser, and the app reads it the same", () {
    final p = Pairing(
      hosts: const ['192.168.1.20', '100.64.0.7', '127.0.0.1'],
      port: 47823,
      key: Pairing.newKey(),
      name: 'Studio Mac',
      device: Pairing.newDevice(),
    );
    expect(p.webLink, startsWith('http://192.168.1.20:47823/#helmy-pair:v2?'));
    final back = Pairing.parse(p.webLink)!;
    expect(back.link, p.link);
    expect(back.key, p.key);
    expect(back.hosts, p.hosts);
    // The key rides after the #, which a browser never sends.
    expect(Uri.parse(p.webLink).query, isEmpty);
    expect(Pairing.parse('http://192.168.1.20:47823/'), isNull);
    expect(Pairing.parse('https://example.com/#nothing'), isNull);
  });

  test("the Wi-Fi's address comes first, then virtual networks, then Tailscale's", () {
    expect(RemoteServer.addressRank('en0', '10.1.1.216'), 0);
    expect(RemoteServer.addressRank('Wi-Fi', '192.168.1.5'), 0);
    expect(RemoteServer.addressRank('bridge100', '192.168.64.1'), 1);
    expect(RemoteServer.addressRank('vEthernet (WSL)', '172.20.0.1'), 1);
    expect(RemoteServer.addressRank('docker0', '172.17.0.1'), 1);
    expect(RemoteServer.addressRank('utun4', '100.101.7.3'), 2);
    expect(RemoteServer.addressRank('tailscale0', '100.64.0.7'), 2);
    // 100.x outside Tailscale's range is an ordinary address.
    expect(RemoteServer.addressRank('en0', '100.10.0.2'), 0);
  });

  group('served', () {
    late Directory root;
    late SessionRepositoryLocal sessions;
    late ConversationRepositoryEngines repo;
    RemoteServer? server;
    const port = 47951;
    final client = HttpClient()..autoUncompress = false;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('remote-page');
      final storage = storageAt(root);
      sessions = SessionRepositoryLocal(storage);
      final meter = UsageMeter();
      repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
    });
    tearDown(() async {
      await server?.stop();
      repo.dispose();
      await deleteFolder(root);
    });

    Future<RemoteServer> serve(Uint8List? page) async {
      final s = server = RemoteServer(
        sessions: sessions,
        conversations: repo,
        port: port,
        page: () async => page,
      );
      await s.start(Pairing.newKey());
      return s;
    }

    Future<HttpClientResponse> get(String path, {bool gzipOk = true, String? tag}) async {
      final req = await client.get('127.0.0.1', port, path);
      if (!gzipOk) req.headers.removeAll(HttpHeaders.acceptEncodingHeader);
      if (tag != null) req.headers.set(HttpHeaders.ifNoneMatchHeader, tag);
      return req.close();
    }

    Future<String> text(HttpClientResponse r, {bool gz = true}) async {
      final bytes = await r.fold<List<int>>([], (a, b) => a..addAll(b));
      return utf8.decode(gz ? gzip.decode(bytes) : bytes);
    }

    test('the page and its files, gzipped as packed, and "not changed" when not', () async {
      await serve(
        pack({
          'index.html': '<title>Helmy</title>',
          'main.dart.js': 'main()',
          'canvaskit/canvaskit.wasm': 'w',
        }),
      );
      final page = await get('/');
      expect(page.statusCode, 200);
      expect(page.headers.contentType?.mimeType, 'text/html');
      expect(page.headers.value(HttpHeaders.contentEncodingHeader), 'gzip');
      expect(page.headers.value('referrer-policy'), 'no-referrer');
      expect(await text(page), '<title>Helmy</title>');

      final js = await get('/main.dart.js');
      expect(js.headers.contentType?.mimeType, 'text/javascript');
      expect(await text(js), 'main()');

      final wasm = await get('/canvaskit/canvaskit.wasm', gzipOk: false);
      expect(wasm.headers.contentType?.mimeType, 'application/wasm');
      expect(wasm.headers.value(HttpHeaders.contentEncodingHeader), isNull);
      expect(await text(wasm, gz: false), 'w');

      final tag = page.headers.value(HttpHeaders.etagHeader);
      final again = await get('/', tag: tag);
      expect(again.statusCode, 304);
      await again.drain<void>();

      final none = await get('/nothing.js');
      expect(none.statusCode, 404);
      await none.drain<void>();
    });

    test('a build without the page says so, in words, to the browser', () async {
      await serve(null);
      final r = await get('/');
      expect(r.statusCode, 200);
      expect(await text(r, gz: false), contains('no page for phone browsers'));
    });
  });
}
