import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A connection to a Chromium browser over its DevTools protocol: commands
/// with their answers, and the events it sends.
class Cdp {
  Cdp._(this._socket) {
    _socket.listen(
      (raw) {
        final m = jsonDecode(raw as String) as Map<String, Object?>;
        if (m['id'] case final int id) {
          final c = _pending.remove(id);
          if (m['error'] case final Map e) {
            c?.completeError(CdpError('${e['message']}'));
          } else {
            c?.complete((m['result'] as Map?)?.cast<String, Object?>() ?? const {});
          }
        } else {
          _events.add(m);
        }
      },
      onDone: _closed,
      onError: (_) => _closed(),
    );
  }

  static Future<Cdp> connect(String url) async => Cdp._(await WebSocket.connect(url));

  final WebSocket _socket;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _events = StreamController<Map<String, Object?>>.broadcast();
  var _id = 0;
  bool _open = true;

  /// Every event, with its `method`, `params` and the `sessionId` it is for.
  Stream<Map<String, Object?>> get events => _events.stream;

  bool get isOpen => _open;

  void _closed() {
    _open = false;
    for (final c in _pending.values) {
      c.completeError(CdpError('The browser closed.'));
    }
    _pending.clear();
  }

  /// Sends [method], for the page [session] when given; its result.
  Future<Map<String, Object?>> send(
    String method, [
    Map<String, Object?> params = const {},
    String? session,
  ]) {
    if (!_open) return Future.error(CdpError('The browser closed.'));
    final c = Completer<Map<String, Object?>>();
    _pending[++_id] = c;
    _socket.add(jsonEncode({'id': _id, 'method': method, 'params': params, 'sessionId': ?session}));
    return c.future;
  }

  Future<void> close() async {
    _open = false;
    await _socket.close();
  }
}

class CdpError implements Exception {
  CdpError(this.message);
  final String message;
  @override
  String toString() => message;
}
