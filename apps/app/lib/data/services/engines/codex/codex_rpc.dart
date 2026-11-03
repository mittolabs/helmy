import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// `codex app-server`: JSON-RPC over stdin and stdout, one message per line.
class CodexRpc {
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

  static Future<CodexRpc> start({
    required String binary,
    required Map<String, String> environment,
    required String cwd,
  }) async {
    final process = await Process.start(
      binary,
      ['app-server'],
      workingDirectory: cwd,
      environment: environment,
      includeParentEnvironment: false,
    );
    return CodexRpc._(process);
  }

  final Process _process;
  final _incoming = StreamController<Map<String, Object?>>.broadcast();
  final _stderr = StringBuffer();
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  int _nextId = 0;
  int? _exitCode;
  bool _closed = false;

  /// Notifications, and requests the server makes of us (those carry an `id`).
  Stream<Map<String, Object?>> get incoming => _incoming.stream;
  String get stderrTail => _stderr.toString();
  int? get exitCode => _exitCode;

  /// Resolves with the result, or throws the error the server answered with.
  Future<Map<String, Object?>> request(String method, Map<String, Object?> params) {
    final id = ++_nextId;
    final done = _pending[id] = Completer();
    _write({'id': id, 'method': method, 'params': params});
    return done.future;
  }

  void notify(String method, Map<String, Object?> params) =>
      _write({'method': method, 'params': params});

  void reply(Object id, Map<String, Object?> result) => _write({'id': id, 'result': result});

  void replyError(Object id, String message) => _write({
    'id': id,
    'error': {'code': -32601, 'message': message},
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
    _process.stdin.writeln(jsonEncode(message));
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
        done.completeError(CodexError(error['message'] as String? ?? '$error'));
      } else {
        done.complete((m['result'] as Map?)?.cast<String, Object?>() ?? {});
      }
      return;
    }
    _incoming.add(m);
  }

  Future<void> _onDone() async {
    _closed = true;
    _exitCode = await _process.exitCode;
    for (final p in _pending.values) {
      p.completeError(CodexError('Codex exited'));
    }
    _pending.clear();
    await _incoming.close();
  }
}

class CodexError implements Exception {
  new(this.message);
  final String message;
  @override
  String toString() => message;
}
