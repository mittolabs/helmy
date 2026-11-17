import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/format.dart' show scratchRoot;
import 'vault.dart';

/// `helmy run <command>`: a command in a terminal with the vault's secrets
/// for its folder, as 1Password's `op run` does. A script on the PATH asks
/// the running Helmy over a socket only this user can open; nothing is
/// written to disk. Agents may not use it (Approvals.offLimits): theirs is
/// vault_run, which blanks the values.
///
/// On macOS and Linux. Not on Windows yet: Dart has no socket there that only
/// this user can open (no Unix sockets, no named pipes), and a port on
/// localhost is open to every program, so it would need a token of its own.
abstract final class HelmyRunCli {
  /// Whether it can be set up here.
  static bool get here => !Platform.isWindows;

  /// Why not, where it cannot.
  static const notHere =
      'Not on Windows yet: Helmy hands secrets out over a socket only you can open, which '
      "Helmy can't open on Windows yet. Helmy itself still runs commands with them.";

  static String get _bin => '${Platform.environment['HOME']}/.local/bin';
  static String get script => '$_bin/helmy';

  /// The socket Helmy hands secrets out on, in its own folder.
  static String socketIn(String supportDir) => '$supportDir/run.sock';

  static bool installed() => File(script).existsSync();

  /// Helmy's own folder, where its socket is: beside the scratch folder.
  static String? get supportDir {
    final root = scratchRoot;
    return root?.substring(0, root.lastIndexOf('/'));
  }

  /// Puts the script on the PATH; why not, or null.
  static Future<String?> install({String? dir}) async {
    if (!here) return notHere;
    final support = dir ?? supportDir;
    if (support == null) return "It couldn't be set up: Helmy's folder isn't known yet.";
    try {
      await Directory(_bin).create(recursive: true);
      final f = File(script);
      await f.writeAsString(scriptFor(socketIn(support)));
      await Process.run('chmod', ['755', f.path]);
    } on Object catch (e) {
      return "It couldn't be set up: $e";
    }
    final path = (Platform.environment['PATH'] ?? '').split(':');
    if (!path.contains(_bin)) {
      return 'Set up, but ~/.local/bin is not on your PATH: add it in your shell profile to use '
          'helmy run.';
    }
    return null;
  }

  /// The script, asking at [socket]. Bash, on macOS and Linux alike.
  static String scriptFor(String socket) =>
      '#!/usr/bin/env bash\n'
      "sock='${socket.replaceAll("'", r"'\''")}'\n"
      '$_script';

  static const _script = r'''
# helmy run: a command with the secrets in Helmy's vault for this folder.
# Set up by Helmy (Settings, Vault). Helmy has to be open.
if [[ "$1" != "run" || -z "$2" ]]; then
  echo "Usage: helmy run <command> [arguments...]" >&2
  exit 64
fi
shift
# base64's decode flag: -d on Linux and newer macOS, -D on older macOS.
if base64 -d </dev/null >/dev/null 2>&1; then d=-d; else d=-D; fi
if [[ ! -S "$sock" ]]; then
  echo "helmy: open Helmy first; it hands out the secrets." >&2
  exit 69
fi
lines=$(curl -sf --unix-socket "$sock" -H "X-Folder: $PWD" "http://helmy/env") || {
  echo "helmy: Helmy didn't answer. Is it open?" >&2
  exit 69
}
while IFS=' ' read -r name value; do
  if [[ "$name" == "!" ]]; then
    echo "helmy: $(printf %s "$value" | base64 $d)" >&2
    continue
  fi
  [[ -n "$name" ]] && export "$name=$(printf %s "$value" | base64 $d)"
done <<< "$lines"
exec "$@"
''';
}

/// Helmy's side of `helmy run`: the secrets for a folder, over a socket
/// only this user can open.
class HelmyRunServer {
  HelmyRunServer(this._vault);
  final Vault _vault;
  HttpServer? _server;

  Future<void> start(String supportDir) async {
    final path = HelmyRunCli.socketIn(supportDir);
    try {
      final old = File(path);
      if (old.existsSync()) old.deleteSync();
      final server = _server = await HttpServer.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      await Process.run('chmod', ['600', path]);
      server.listen((r) => unawaited(_serve(r)));
    } on Object {
      // No socket: helmy run says Helmy didn't answer.
    }
  }

  Future<void> _serve(HttpRequest r) async {
    final res = r.response;
    try {
      final folder = r.headers.value('x-folder') ?? '';
      if (r.uri.path != '/env' || folder.isEmpty) {
        res.statusCode = HttpStatus.notFound;
        return await res.close();
      }
      final problems = <String>[];
      final env = await _vault.envFor(projectFor(folder, _vault.all.keys), problems: problems);
      res.headers.contentType = ContentType.text;
      // What could not be fetched, said in the terminal.
      for (final p in problems) {
        res.writeln('! ${base64.encode(utf8.encode(p))}');
      }
      for (final e in env.entries) {
        res.writeln('${e.key} ${base64.encode(utf8.encode(e.value))}');
      }
      await res.close();
    } on Object {
      res.statusCode = HttpStatus.internalServerError;
      await res.close();
    }
  }

  /// The project [folder] is in: the deepest one with secrets that holds it,
  /// else [folder] itself (it gets the shared ones).
  static String projectFor(String folder, Iterable<String> scopes) {
    String? best;
    for (final s in scopes) {
      if (s == sharedScope) continue;
      if ((folder == s || folder.startsWith('$s/')) && (best == null || s.length > best.length)) {
        best = s;
      }
    }
    return best ?? folder;
  }

  Future<void> stop() async => _server?.close(force: true);
}
