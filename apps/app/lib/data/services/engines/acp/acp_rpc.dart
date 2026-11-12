import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// An Agent Client Protocol agent: JSON-RPC over its stdin and stdout, one
/// message per line.
class AcpRpc {
  new _(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onDone);
    _process.stderr.transform(utf8.decoder).listen((s) {
      _stderr.write(s);
      if (_stderr.length > 8000) {
        final tail = _stderr.toString().substring(_stderr.length - 4000);
        _stderr
          ..clear()
          ..write(tail);
      }
    });
  }

  static Future<AcpRpc> start({
    required String command,
    required List<String> args,
    required Map<String, String> environment,
    required String cwd,
  }) async => AcpRpc._(
    await Process.start(
      command,
      args,
      workingDirectory: cwd,
      environment: environment,
      includeParentEnvironment: false,
    ),
  );

  final Process _process;

  /// The agent's process: the commands it runs are under it.
  int get pid => _process.pid;
  final _incoming = StreamController<Map<String, Object?>>.broadcast();
  final _stderr = StringBuffer();
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  int _nextId = 0;
  int? _exitCode;
  bool _closed = false;

  /// Notifications, and requests the agent makes of us (those carry an `id`).
  Stream<Map<String, Object?>> get incoming => _incoming.stream;
  String get stderrTail => _stderr.toString();
  int? get exitCode => _exitCode;
  bool get closed => _closed;

  /// Resolves with the result, or throws the [AcpError] the agent answered.
  Future<Map<String, Object?>> request(String method, Map<String, Object?> params) {
    final id = ++_nextId;
    final done = _pending[id] = Completer();
    _write({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return done.future;
  }

  void notify(String method, Map<String, Object?> params) =>
      _write({'jsonrpc': '2.0', 'method': method, 'params': params});

  void reply(Object id, Object? result) => _write({'jsonrpc': '2.0', 'id': id, 'result': result});

  void replyError(Object id, int code, String message) => _write({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _process.stdin.close().catchError((_) {});
    await _process.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _process.kill();
        return -1;
      },
    );
  }

  void _write(Map<String, Object?> message) {
    if (_closed) return;
    try {
      _process.stdin.writeln(jsonEncode(message));
    } on Object {
      // The agent has gone; its end is reported by [incoming] closing.
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      _stderr.writeln(line);
      return;
    }
    if (decoded is! Map) return;
    final m = decoded.cast<String, Object?>();
    final id = m['id'];
    if (m['method'] == null && id is int) {
      final done = _pending.remove(id);
      if (done == null) return;
      final error = m['error'];
      if (error is Map) {
        done.completeError(
          AcpError(error['message'] as String? ?? '$error', code: error['code'] as int?),
        );
      } else {
        final r = m['result'];
        done.complete(r is Map ? r.cast<String, Object?>() : {});
      }
      return;
    }
    _incoming.add(m);
  }

  Future<void> _onDone() async {
    _closed = true;
    _exitCode = await _process.exitCode;
    for (final p in _pending.values) {
      p.completeError(AcpError('The agent exited'));
    }
    _pending.clear();
    await _incoming.close();
  }
}

class AcpError implements Exception {
  new(this.message, {this.code});
  final String message;
  final int? code;

  /// The agent needs signing in first.
  bool get authRequired => code == -32000 || message.toLowerCase().contains('auth');

  @override
  String toString() => message;
}
