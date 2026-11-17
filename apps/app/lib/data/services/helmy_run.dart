import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:helmy_cli/run_protocol.dart';

import 'vault.dart';

/// `helmy run <command>`: a command in a terminal with the vault's secrets
/// for its folder, as 1Password's `op run` does. The command is a program
/// of its own (apps/cli), built for each system and shipped inside
/// Helmy as helmy-cli; Settings puts a copy on the PATH as `helmy`. It asks
/// the running Helmy over loopback with a token only this user can read;
/// nothing is written to disk. Agents may not use it (Approvals.offLimits):
/// theirs is vault_run, which blanks the values.
abstract final class HelmyRunCli {
  static final _windows = Platform.isWindows;
  static Map<String, String> get _env => Platform.environment;

  /// The command as shipped, beside Helmy's own program.
  static String get bundled =>
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}helmy-cli${_windows ? '.exe' : ''}';

  /// Whether this Helmy has it to set up (a build from source may not).
  static bool get here => File(bundled).existsSync();

  /// Why not, where it cannot.
  static const notHere =
      "This copy of Helmy doesn't include the helmy command. Helmy itself still runs "
      'commands with your secrets.';

  /// Where it is put: on macOS and Linux the usual folder for a person's own
  /// commands; on Windows Helmy's own, added to the PATH.
  static String get binDir => _windows
      ? '${_env['LOCALAPPDATA'] ?? '${_env['USERPROFILE']}\\AppData\\Local'}\\Helmy\\bin'
      : '${_env['HOME']}/.local/bin';
  static String get script => '$binDir${Platform.pathSeparator}helmy${_windows ? '.exe' : ''}';

  static bool installed() => File(script).existsSync();

  /// Puts the command on the PATH; why not, or null.
  static Future<String?> install() async {
    if (!here) return notHere;
    try {
      await Directory(binDir).create(recursive: true);
      await _copy();
    } on Object catch (e) {
      return "It couldn't be set up: $e";
    }
    if (_windows) {
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', addToPathScript],
        environment: {'HELMY_BIN': binDir},
      );
      if (r.exitCode != 0) {
        return 'Set up in $binDir, but it couldn\'t be added to your PATH: add that folder to use '
            'helmy run.';
      }
      return null;
    }
    final path = (_env['PATH'] ?? '').split(':');
    if (!path.contains(binDir)) {
      return 'Set up, but ~/.local/bin is not on your PATH: add it in your shell profile to use '
          'helmy run.';
    }
    return null;
  }

  /// Keeps the copy on the PATH the one this Helmy ships: after an update,
  /// or in place of the script earlier versions put there.
  static Future<void> refresh() async {
    if (!here || !installed()) return;
    try {
      final have = File(script), ship = File(bundled);
      if (await have.length() == await ship.length() &&
          _same(await have.readAsBytes(), await ship.readAsBytes())) {
        return;
      }
      await _copy();
    } on Object {
      // In use by a running helmy run (Windows): next time.
    }
  }

  static bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<void> _copy() async {
    // Beside it first, then moved over: a half-written command never runs.
    final tmp = '$script.new';
    await File(bundled).copy(tmp);
    if (!_windows) await Process.run('chmod', ['755', tmp]);
    // Copied out of a downloaded app, it would carry the download's
    // quarantine, and macOS would refuse to run it from a terminal.
    if (Platform.isMacOS) await Process.run('xattr', ['-d', 'com.apple.quarantine', tmp]);
    await File(tmp).rename(script);
  }

  /// Adds $env:HELMY_BIN to the person's own PATH, kept as written (with
  /// its %VARIABLES%), and tells open programs the PATH changed.
  static const addToPathScript = r'''
$key = 'HKCU:\Environment'
$path = (Get-Item $key).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$parts = @($path -split ';' | Where-Object { $_ })
if ($parts -notcontains $env:HELMY_BIN) {
  New-ItemProperty -Path $key -Name Path -PropertyType ExpandString -Force -Value (($parts + $env:HELMY_BIN) -join ';') | Out-Null
  [Environment]::SetEnvironmentVariable('HELMY_PATH_CHANGED', '1', 'User')
  [Environment]::SetEnvironmentVariable('HELMY_PATH_CHANGED', $null, 'User')
}
''';
}

/// Helmy's side of `helmy run`: the secrets for a folder, over loopback, to
/// whoever has the token in the run file (only this user can read it).
class HelmyRunServer {
  HelmyRunServer(this._vault, {String? file})
    : _file = file ?? runFile(os: Platform.operatingSystem, env: Platform.environment);
  final Vault _vault;
  final String _file;
  HttpServer? _server;
  late final String _token = [
    for (var i = 0; i < 32; i++) Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  Future<void> start() async {
    try {
      final server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) => unawaited(_serve(r)));
      final f = File(_file);
      await f.parent.create(recursive: true);
      // Made readable by this user alone before the token goes in. On
      // Windows the folder (in the person's own AppData) already is.
      await f.writeAsString('');
      if (!Platform.isWindows) await Process.run('chmod', ['600', f.path]);
      await f.writeAsString(runFileJson(server.port, _token), flush: true);
    } on Object {
      // No server: helmy run says Helmy didn't answer.
    }
  }

  Future<void> _serve(HttpRequest r) async {
    final res = r.response;
    try {
      final token = r.headers.value(tokenHeader) ?? '';
      final folder = Uri.decodeComponent(r.headers.value(folderHeader) ?? '');
      // A web page could reach loopback too: it sends an Origin, and never
      // has the token.
      if (r.uri.path != '/env' ||
          r.headers.value('origin') != null ||
          !sameToken(token, _token) ||
          folder.isEmpty) {
        res.statusCode = HttpStatus.notFound;
        return await res.close();
      }
      final problems = <String>[];
      final env = await _vault.envFor(projectFor(folder, _vault.all.keys), problems: problems);
      res.headers.contentType = ContentType.json;
      res.write(encodeAnswer((env: env, problems: problems)));
      await res.close();
    } on Object {
      res.statusCode = HttpStatus.internalServerError;
      await res.close();
    }
  }

  /// The project [folder] is in: the deepest one with secrets that holds it,
  /// else [folder] itself (it gets the shared ones). Either slash separates
  /// folders, as Windows writes them either way.
  static String projectFor(String folder, Iterable<String> scopes) {
    String? best;
    for (final s in scopes) {
      if (s == sharedScope) continue;
      final inside = folder == s || folder.startsWith('$s/') || folder.startsWith('$s\\');
      if (inside && (best == null || s.length > best.length)) best = s;
    }
    return best ?? folder;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    try {
      File(_file).deleteSync();
    } on Object {
      // Already gone.
    }
  }
}
