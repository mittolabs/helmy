import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:helmy_relay/protocol.dart';

import 'remote_crypto.dart';
import 'remote_server.dart';

/// Helmy Connect, on this computer: a line kept open to the relay, so a
/// paired phone reaches Helmy from anywhere, with no port opened here and
/// no app or account on the phone. Every phone through it is handed to
/// [RemoteServer] as if it had connected on this network; what it says is
/// sealed with its own key, which the relay never has.
///
/// This computer is known to the relay by its own key ([seed]), so nobody
/// else can stand in for it there.
class RelayHost extends ChangeNotifier {
  RelayHost(this._server, {required this.seed, this.url = Pairing.defaultRelay});

  final RemoteServer _server;

  /// This computer's Ed25519 seed, base64url.
  final String seed;

  /// The relay's WebSocket address.
  final String url;

  /// This computer's id on the relay; known before it connects.
  String? id;

  /// Whether the relay has this computer now.
  bool connected = false;

  /// Why it is not, in words; null while connected or trying.
  String? trouble;

  WebSocket? _ws;
  Timer? _retry;
  int _attempt = 0;
  bool _stopped = true;
  final _pipes = <int, _RelayPipe>{};

  /// A new seed for a computer's key on the relay.
  static String newSeed() => Pairing.newKey();

  static Future<SimpleKeyPair> _pair(String seed) =>
      Ed25519().newKeyPairFromSeed(base64Url.decode(base64Url.normalize(seed)));

  /// The id the relay knows the computer with [seed] by.
  static Future<String> idFor(String seed) async =>
      hostId((await (await _pair(seed)).extractPublicKey()).bytes);

  Future<void> start() async {
    _stopped = false;
    id ??= await idFor(seed);
    await _connect();
  }

  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    await _ws?.close();
    _ws = null;
    _endPipes();
    connected = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> _connect() async {
    _retry?.cancel();
    if (_stopped) return;
    try {
      final ws = await WebSocket.connect('$url/host').timeout(const Duration(seconds: 10));
      ws.pingInterval = const Duration(seconds: 20);
      final said = StreamIterator<Object?>(ws);
      if (!await said.moveNext().timeout(const Duration(seconds: 10))) throw 'closed';
      final nonce = '${jsonDecode('${said.current}')['nonce']}';
      final pair = await _pair(seed);
      final sig = await Ed25519().sign(challengeText(nonce), keyPair: pair);
      ws.add(
        jsonEncode({
          'type': 'host',
          'pub': base64Url.encode((await pair.extractPublicKey()).bytes),
          'sig': base64Url.encode(sig.bytes),
        }),
      );
      if (!await said.moveNext().timeout(const Duration(seconds: 10))) {
        throw 'The relay turned this computer away (${ws.closeReason ?? ws.closeCode}).';
      }
      final ready = jsonDecode('${said.current}');
      if (_stopped) {
        await ws.close();
        return;
      }
      _ws = ws;
      id = '${ready['id']}';
      connected = true;
      trouble = null;
      _attempt = 0;
      if (!_disposed) notifyListeners();
      try {
        while (await said.moveNext()) {
          if (said.current case final List<int> bytes) _frame(bytes);
        }
      } on Object {
        // Its socket broke.
      }
      _lost(
        ws.closeCode == RelayClose.replaced
            ? 'Another copy of Helmy with this computer\'s key connected to the relay.'
            : null,
      );
    } on Object catch (e) {
      _lost(e is String ? e : null);
    }
  }

  void _lost([String? why]) {
    _ws = null;
    _endPipes();
    if (_stopped) return;
    connected = false;
    if (_disposed) return;
    trouble =
        why ??
        "Can't reach Helmy Connect (${Uri.parse(url).host}). Phones still reach this computer "
            'on the same network. Trying again.';
    notifyListeners();
    // Again soon, then less often: 2, 4, 8, up to 60 seconds.
    final wait = Duration(seconds: (2 << _attempt.clamp(0, 5)).clamp(2, 60));
    _attempt++;
    _retry = Timer(wait, () => unawaited(_connect()));
  }

  void _frame(List<int> bytes) {
    final f = Frame.decode(bytes);
    if (f == null) return;
    switch (f.kind) {
      case FrameKind.open:
        final pipe = _pipes[f.channel] = _RelayPipe(this, f.channel);
        unawaited(_server.accept(pipe, f.query));
      case FrameKind.text:
        _pipes[f.channel]?._in.add(f.text);
      case FrameKind.binary:
        _pipes[f.channel]?._in.add(f.payload);
      case FrameKind.close:
        unawaited(_pipes.remove(f.channel)?._in.close());
    }
  }

  void _send(Frame f) {
    try {
      _ws?.add(f.encode());
    } on Object {
      // Closing: the phone hears when the relay notices.
    }
  }

  void _endPipes() {
    for (final p in _pipes.values) {
      unawaited(p._in.close());
    }
    _pipes.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }

  bool _disposed = false;
}

/// One phone through the relay: a channel on this computer's line to it.
class _RelayPipe implements RemotePipe {
  _RelayPipe(this._host, this._channel);

  final RelayHost _host;
  final int _channel;
  final _in = StreamController<Object?>();

  @override
  Stream<Object?> get messages => _in.stream;

  @override
  void add(Object data) => _host._send(
    data is String
        ? Frame.text(_channel, data)
        : Frame(FrameKind.binary, _channel, Uint8List.fromList(data as List<int>)),
  );

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_host._pipes.remove(_channel) == null) return;
    _host._send(Frame.close(_channel, code ?? 1000, reason ?? ''));
    // Not waited for: with nobody listening, it would never finish.
    unawaited(_in.close());
  }
}
