import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../utils/platform.dart';
import '../../cli_locator.dart';

/// Keeps the model server on this computer (Ollama) answering. It can stop,
/// or get stuck unloading a model ("Stopping..." in `ollama ps`) after a
/// request timed out, and then every request waits forever. The doctor
/// notices both and restarts it the way it was installed, at most once in a
/// while, so a server that will not come back is not restarted in a loop.
class OllamaDoctor {
  static const host = 'http://127.0.0.1:11434';
  static DateTime? _lastRestart;

  /// How long to leave between restarts.
  static const rest = Duration(minutes: 2);

  static Future<Object?> _get(String path, {Duration timeout = const Duration(seconds: 3)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse('$host$path')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      return jsonDecode(await utf8.decodeStream(res).timeout(timeout));
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Whether it answers at all.
  static Future<bool> answers() async => await _get('/api/version') != null;

  /// Whether a model has been unloading for longer than it should: past the
  /// time it was due to go, and still there.
  static Future<bool> stuck({DateTime? now}) async {
    final ps = await _get('/api/ps');
    if (ps is! Map) return false;
    return isStuck(ps, now ?? DateTime.now());
  }

  /// [ps] (what `/api/ps` answers) shows a model due to have gone a while ago.
  static bool isStuck(Map ps, DateTime now) {
    for (final m in (ps['models'] as List? ?? const []).whereType<Map>()) {
      final due = DateTime.tryParse('${m['expires_at'] ?? ''}');
      if (due != null && now.difference(due) > const Duration(seconds: 30)) return true;
    }
    return false;
  }

  /// Makes sure it is not stuck: restarts it when it is. A stopped one is
  /// started only when [start]: stopping it may have been the user's choice,
  /// and a model loaded for nothing costs memory. True when it answers after.
  static Future<bool> ensure({bool start = false}) async {
    final up = await answers();
    if (up && !await stuck()) return true;
    if (!up && !start) return false;
    final last = _lastRestart;
    if (last != null && DateTime.now().difference(last) < rest) return up;
    _lastRestart = DateTime.now();
    if (!await _restart()) return up;
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (await answers()) return true;
    }
    return false;
  }

  /// Restarts it as it was installed: Homebrew's service, the desktop app, or
  /// the command run by itself. False when it is not installed here.
  static Future<bool> _restart() async {
    final ollama = await CliLocator().find('ollama');
    Future<bool> ran(String cmd, List<String> args) async {
      try {
        return (await Process.run(cmd, args)).exitCode == 0;
      } on Object {
        return false;
      }
    }

    Future<bool> serve() async {
      if (ollama == null) return false;
      await Process.start(ollama, ['serve'], mode: ProcessStartMode.detached);
      return true;
    }

    switch (Desktop.current) {
      case .mac:
        final brew = await CliLocator().find('brew');
        if (brew != null) {
          final list = await Process.run(brew, ['services', 'list']);
          if ('${list.stdout}'.contains(RegExp(r'^ollama\s', multiLine: true))) {
            return ran(brew, ['services', 'restart', 'ollama']);
          }
        }
        await ran('pkill', ['-x', 'ollama']);
        if (Directory('/Applications/Ollama.app').existsSync()) {
          return ran('open', ['-a', 'Ollama']);
        }
        return serve();
      case .windows:
        await ran('taskkill', ['/F', '/IM', 'ollama.exe']);
        final app = '${Platform.environment['LOCALAPPDATA']}\\Programs\\Ollama\\ollama app.exe';
        if (File(app).existsSync()) {
          await Process.start(app, const [], mode: ProcessStartMode.detached);
          return true;
        }
        return serve();
      case .linux:
        // A system service needs an administrator to restart: left alone.
        if (await ran('systemctl', ['is-active', '--quiet', 'ollama'])) return false;
        await ran('pkill', ['-x', 'ollama']);
        return serve();
    }
  }
}
