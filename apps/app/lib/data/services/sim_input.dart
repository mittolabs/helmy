import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Input for iOS simulators that costs milliseconds: Helmy's helper
/// (`tool/sim_input`), one per simulator, kept connected, built on the
/// frameworks AXe installs. The `axe` command connects afresh for every
/// tap, about two seconds each. Where the helper cannot run (AXe moved, its
/// frameworks changed), [send] says so and the caller uses `axe` instead.
class SimInput {
  SimInput({required this._helper, required this._appData, required this._axe});

  final Future<Uint8List> Function() _helper;
  final Future<Directory> Function() _appData;
  final Future<String?> Function() _axe;

  final _running = <String, _Helper>{};

  /// When a simulator's helper last failed to start: not tried again for a
  /// minute, so a broken one does not cost each tap a failed start.
  final _failed = <String, DateTime>{};

  Future<String?>? _binary;

  /// The helper, copied out of the app where it can run (again when the
  /// app's copy changed).
  Future<String?> _path() => _binary ??= () async {
    try {
      final bytes = await _helper();
      final dir = Directory('${(await _appData()).path}/bin');
      await dir.create(recursive: true);
      final file = File('${dir.path}/sim_input');
      if (!file.existsSync() ||
          file.lengthSync() != bytes.length ||
          !_same(await file.readAsBytes(), bytes)) {
        await file.writeAsBytes(bytes, flush: true);
      }
      final chmod = await Process.run('/bin/chmod', ['755', file.path]);
      return chmod.exitCode == 0 ? file.path : null;
    } on Object {
      return null;
    }
  }();

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Where AXe's frameworks are, beside the `axe` that was found.
  Future<String?> _frameworks() async {
    final axe = await _axe();
    if (axe == null) return null;
    try {
      final real = await File(axe).resolveSymbolicLinks();
      final dir = Directory('${File(real).parent.parent.path}/libexec/Frameworks');
      return dir.existsSync() ? dir.path : null;
    } on Object {
      return null;
    }
  }

  Future<_Helper?> _for(String udid) async {
    final live = _running[udid];
    if (live != null && !live.gone) return live;
    _running.remove(udid);
    final failed = _failed[udid];
    if (failed != null && DateTime.now().difference(failed) < const Duration(minutes: 1)) {
      return null;
    }
    final path = await _path();
    final frameworks = await _frameworks();
    if (path == null || frameworks == null || !Platform.isMacOS) {
      _failed[udid] = DateTime.now();
      return null;
    }
    final helper = await _Helper.start(path, udid, frameworks);
    if (helper == null) {
      _failed[udid] = DateTime.now();
      return null;
    }
    _failed.remove(udid);
    return _running[udid] = helper;
  }

  /// Does [action] on simulator [udid]: true when done, false when the
  /// simulator refused it, null when the helper cannot run here (use `axe`).
  Future<bool?> send(String udid, Map<String, Object?> action) async {
    final helper = await _for(udid);
    if (helper == null) return null;
    final answer = await helper.send(action);
    if (answer == null) return null;
    return answer == 'ok';
  }

  Future<bool?> tap(String udid, double x, double y) => send(udid, {'do': 'tap', 'x': x, 'y': y});

  Future<bool?> swipe(String udid, (double, double) from, (double, double) to) =>
      send(udid, {'do': 'swipe', 'x1': from.$1, 'y1': from.$2, 'x2': to.$1, 'y2': to.$2});

  /// [code] is a USB keyboard usage: Return 40, Backspace 42.
  Future<bool?> key(String udid, int code) => send(udid, {'do': 'key', 'code': code});

  Future<bool?> home(String udid) => send(udid, {'do': 'button', 'name': 'home'});

  /// Text a US keyboard can type; false when it has a character it cannot.
  Future<bool?> text(String udid, String text) => send(udid, {'do': 'text', 'text': text});

  /// Ends every helper (they also end with Helmy, when their input closes).
  void dispose() {
    for (final h in _running.values) {
      h.stop();
    }
    _running.clear();
  }
}

/// One running helper: actions in, one line back for each, in order.
class _Helper {
  _Helper._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_line, onDone: _end, onError: (_) => _end());
    _process.stderr.drain<void>().ignore();
    // Writing to a helper that has just ended fails here, not at the write.
    _process.stdin.done.ignore();
    unawaited(_process.exitCode.then((_) => _end()));
  }

  final Process _process;
  final _waiting = Queue<Completer<String?>>();
  final _ready = Completer<bool>();
  bool gone = false;

  static Future<_Helper?> start(String path, String udid, String frameworks) async {
    try {
      final process = await Process.start(
        path,
        [udid],
        environment: {'DYLD_FRAMEWORK_PATH': frameworks},
      );
      final helper = _Helper._(process);
      final ready = await helper._ready.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
      if (!ready) {
        helper.stop();
        return null;
      }
      return helper;
    } on Object {
      return null;
    }
  }

  void _line(String line) {
    if (!_ready.isCompleted) {
      _ready.complete(line == 'ready');
      return;
    }
    if (_waiting.isNotEmpty) _waiting.removeFirst().complete(line);
  }

  void _end() {
    if (gone) return;
    gone = true;
    if (!_ready.isCompleted) _ready.complete(false);
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(null);
    }
  }

  /// The helper's answer: "ok", "error: …", or null when it has gone.
  Future<String?> send(Map<String, Object?> action) {
    if (gone) return Future.value();
    final done = Completer<String?>();
    _waiting.add(done);
    try {
      _process.stdin.writeln(jsonEncode(action));
    } on Object {
      _end();
    }
    return done.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        // Stuck: ended, so the next action starts it afresh.
        stop();
        return null;
      },
    );
  }

  void stop() {
    _process.kill();
    _end();
  }
}
