/// Helmy Connect's relay: passes sealed messages between a computer and the
/// phones paired with it, so a phone reaches the computer from anywhere
/// without either opening a port. See `protocol.dart` for what they say.
///
/// It keeps nothing: no accounts, no disk. A computer is known by the key
/// it signs with, for as long as its socket is open.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'protocol.dart';

export 'protocol.dart';

/// Limits that keep one computer from taking the relay for itself.
class RelayLimits {
  const RelayLimits({
    this.hosts = 5000,
    this.phonesPerHost = 16,
    this.bytesPerDay = 10 * 1000 * 1000 * 1000,
    this.message = 48 * 1024 * 1024,
  });

  /// Computers connected at once, in all.
  final int hosts;

  /// Phones connected to one computer at once.
  final int phonesPerHost;

  /// What one computer's phones may move through the relay in a day, both
  /// ways together.
  final int bytesPerDay;

  /// The largest single message, either way. A file sent to a phone (up to
  /// 25 MB, base64) fits.
  final int message;
}

class Relay {
  Relay({
    this.limits = const RelayLimits(),
    this.page,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The phone page (the remote built for the web), served at every other
  /// path; null serves none.
  final Directory? page;

  final RelayLimits limits;
  final DateTime Function() _now;
  final _hosts = <String, _Host>{};
  HttpServer? _server;

  /// Computers connected now.
  int get hosts => _hosts.length;

  int get port => _server!.port;

  Future<void> start({InternetAddress? address, int port = 8080}) async {
    final server = _server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    // The page's files, compressed for browsers that take it.
    server.autoCompress = true;
    server.listen((req) => unawaited(_handle(req).catchError((Object _) {})));
  }

  Future<void> stop() async {
    for (final h in [..._hosts.values]) {
      await h.end();
    }
    _hosts.clear();
    await _server?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    switch (req.uri.path) {
      case '/healthz':
        res
          ..headers.contentType = ContentType.text
          ..write('ok');
        await res.close();
      case '/host' when WebSocketTransformer.isUpgradeRequest(req):
        await _host(await WebSocketTransformer.upgrade(req));
      case '/ws' when WebSocketTransformer.isUpgradeRequest(req):
        final query = {...req.uri.queryParameters};
        final id = query.remove('h') ?? '';
        await _phone(await WebSocketTransformer.upgrade(req), id, query);
      default:
        await _page(req);
    }
  }

  /// A file of the phone page; the page itself for any path that is not
  /// one, so the page's own routes load it.
  Future<void> _page(HttpRequest req) async {
    final res = req.response;
    final root = page;
    res.headers
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('X-Frame-Options', 'DENY')
      // Its files keep their names across releases: asked again each time,
      // and "not changed" when they are not.
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (root == null || (req.method != 'GET' && req.method != 'HEAD')) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final parts = req.uri.pathSegments.where((p) => p.isNotEmpty).toList();
    var file = File([root.path, ...parts].join('/'));
    final inside = !parts.any((p) => p == '..' || p.startsWith('.'));
    if (!inside || !await file.exists()) {
      // A missing file with an extension is missing; anything else is a route.
      if (!inside || (parts.isNotEmpty && parts.last.contains('.'))) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      file = File('${root.path}/index.html');
    }
    final stat = await file.stat();
    final tag =
        '"${stat.size.toRadixString(36)}-${stat.modified.millisecondsSinceEpoch.toRadixString(36)}"';
    res.headers.set(HttpHeaders.etagHeader, tag);
    if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == tag) {
      res.statusCode = HttpStatus.notModified;
      await res.close();
      return;
    }
    res.headers.contentType = ContentType.parse(_type(file.path));
    if (req.method == 'GET') await res.addStream(file.openRead());
    await res.close();
  }

  static String _type(String path) =>
      switch (path.split('.').last.toLowerCase()) {
        'html' => 'text/html; charset=utf-8',
        'js' || 'mjs' => 'text/javascript; charset=utf-8',
        'json' => 'application/json',
        'wasm' => 'application/wasm',
        'css' => 'text/css; charset=utf-8',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'svg' => 'image/svg+xml',
        'ico' => 'image/x-icon',
        'otf' => 'font/otf',
        'ttf' => 'font/ttf',
        'woff2' => 'font/woff2',
        _ => 'application/octet-stream',
      };

  /// A computer: challenged, and kept under its id once it proves its key.
  Future<void> _host(WebSocket ws) async {
    ws.pingInterval = const Duration(seconds: 20);
    final nonce = base64Url.encode(
      List.generate(32, (_) => _random.nextInt(256)),
    );
    ws.add(jsonEncode({'type': 'challenge', 'nonce': nonce}));
    final messages = StreamIterator(ws);
    String? id;
    try {
      if (!await messages.moveNext().timeout(const Duration(seconds: 10))) {
        return;
      }
      final m = jsonDecode('${messages.current}');
      final pub = base64Url.decode(base64Url.normalize('${m['pub']}'));
      final sig = base64Url.decode(base64Url.normalize('${m['sig']}'));
      final ok = await Ed25519().verify(
        challengeText(nonce),
        signature: Signature(
          sig,
          publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519),
        ),
      );
      if (ok) id = await hostId(pub);
    } on Object {
      id = null;
    }
    if (id == null) {
      await ws.close(WebSocketStatus.policyViolation, 'not proven');
      return;
    }
    if (_hosts[id] case final old?) {
      await old.end(RelayClose.replaced, 'replaced');
    } else if (_hosts.length >= limits.hosts) {
      await ws.close(RelayClose.full, 'relay full');
      return;
    }
    final host = _hosts[id] = _Host(id, ws, this);
    ws.add(jsonEncode({'type': 'ready', 'id': id}));
    try {
      while (await messages.moveNext()) {
        final data = messages.current;
        if (data is List<int>) host.fromHost(data);
      }
    } on Object {
      // Its socket broke.
    }
    if (_hosts[id] == host) _hosts.remove(id);
    await host.end();
  }

  /// A phone, for computer [id]: a channel on the computer's socket.
  Future<void> _phone(
    WebSocket ws,
    String id,
    Map<String, String> query,
  ) async {
    ws.pingInterval = const Duration(seconds: 20);
    final host = _hosts[id];
    if (host == null) {
      await ws.close(RelayClose.offline, 'offline');
      return;
    }
    if (host.phones.length >= limits.phonesPerHost) {
      await ws.close(RelayClose.busy, 'busy');
      return;
    }
    if (!host.allow(0)) {
      await ws.close(RelayClose.overQuota, 'over quota');
      return;
    }
    final ch = host.next++;
    host.phones[ch] = ws;
    host.send(Frame.open(ch, query));
    ws.listen(
      (data) {
        final bytes = data is String ? utf8.encode(data) : data as List<int>;
        if (bytes.length > limits.message || !host.allow(bytes.length)) {
          unawaited(ws.close(RelayClose.overQuota, 'over quota'));
          return;
        }
        host.send(
          data is String
              ? Frame(FrameKind.text, ch, Uint8List.fromList(bytes))
              : Frame(FrameKind.binary, ch, Uint8List.fromList(bytes)),
        );
      },
      onDone: () {
        if (host.phones.remove(ch) != null) {
          host.send(Frame.close(ch, 1000, ''));
        }
      },
      onError: (Object _) {},
      cancelOnError: true,
    );
  }

  static final _random = Random.secure();
}

class _Host {
  _Host(this.id, this.ws, this.relay) : _day = relay._now();

  final String id;
  final WebSocket ws;
  final Relay relay;
  final phones = <int, WebSocket>{};
  int next = 1;

  DateTime _day;
  int _moved = 0;

  /// Whether [bytes] more may pass today.
  bool allow(int bytes) {
    final now = relay._now();
    if (now.difference(_day) >= const Duration(days: 1)) {
      _day = now;
      _moved = 0;
    }
    _moved += bytes;
    return _moved <= relay.limits.bytesPerDay;
  }

  void send(Frame f) {
    try {
      ws.add(f.encode());
    } on Object {
      // Closing.
    }
  }

  void fromHost(List<int> data) {
    final f = Frame.decode(data);
    if (f == null) return;
    final phone = phones[f.channel];
    if (phone == null) return;
    switch (f.kind) {
      case FrameKind.text:
      case FrameKind.binary:
        if (!allow(f.payload.length)) {
          phones.remove(f.channel);
          unawaited(phone.close(RelayClose.overQuota, 'over quota'));
          return;
        }
        phone.add(f.kind == FrameKind.text ? f.text : f.payload);
      case FrameKind.close:
        phones.remove(f.channel);
        final c = f.closing;
        unawaited(phone.close(_closable(c.code), c.reason));
      case FrameKind.open:
        break;
    }
  }

  /// A code a WebSocket may be closed with, as a computer asked.
  static int _closable(int code) =>
      code == 1000 || (code >= 3000 && code < 5000) ? code : 1000;

  Future<void> end([int code = 1001, String reason = '']) async {
    for (final p in [...phones.values]) {
      await p.close(RelayClose.offline, 'offline');
    }
    phones.clear();
    await ws.close(code, reason);
  }
}
