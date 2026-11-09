import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'vault.dart';

/// `helmy run <command>`: a command in a terminal with the vault's secrets
/// for its folder, as 1Password's `op run` does. A script on the PATH asks
/// the running Helmy over a socket only this user can open; nothing is
/// written to disk. Agents may not use it (Approvals.offLimits): theirs is
/// vault_run, which blanks the values.
abstract final class HelmyRunCli {
  static String get _bin => '${Platform.environment['HOME']}/.local/bin';
  static String get script => '$_bin/helmy';

  /// The socket Helmy hands secrets out on, in its own folder.
  static String socketIn(String supportDir) => '$supportDir/run.sock';

  static bool installed() => File(script).existsSync();

  /// Puts the script on the PATH; why not, or null.
  static Future<String?> install() async {
    try {
      await Directory(_bin).create(recursive: true);
      final f = File(script);
      await f.writeAsString(_script);
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

  static const _script = r'''#!/bin/zsh
# helmy run: a command with the secrets in Helmy's vault for this folder.
# Set up by Helmy (Settings, Vault). Helmy has to be open.
if [[ "$1" != "run" || -z "$2" ]]; then
  echo "Usage: helmy run <command> [arguments...]" >&2
  exit 64
fi
shift
sock="$HOME/Library/Application Support/com.mittolabs.helmy/run.sock"
if [[ ! -S "$sock" ]]; then
  echo "helmy: open Helmy first; it hands out the secrets." >&2
  exit 69
fi
lines=$(curl -sf --unix-socket "$sock" -H "X-Folder: $PWD" "http://helmy/env") || {
  echo "helmy: Helmy didn't answer. Is it open?" >&2
  exit 69
}
while IFS=' ' read -r name value; do
  [[ -n "$name" ]] && export "$name=$(printf %s "$value" | base64 -D)"
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
      final env = await _vault.envFor(projectFor(folder, _vault.all.keys));
      res.headers.contentType = ContentType.text;
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
