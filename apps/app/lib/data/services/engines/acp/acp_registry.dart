import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../cli_locator.dart';
import 'acp_rpc.dart';

/// One agent in the ACP registry, as listed.
class const AcpListing({
  required final String id,
  required final String name,
  final String version = '',
  final String description = '',
  final String? icon,
  final String? website,

  /// How it is installed: `npx`, `uvx` or `binary`, as the registry gives it.
  final Map<String, Object?> distribution = const {},
}) {
  static AcpListing fromJson(Map<String, Object?> j) => AcpListing(
    id: '${j['id']}',
    name: '${j['name'] ?? j['id']}',
    version: '${j['version'] ?? ''}',
    description: '${j['description'] ?? ''}',
    icon: j['icon'] as String?,
    website: j['website'] as String?,
    distribution: (j['distribution'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  /// Whether it can run on this computer.
  bool get runsHere =>
      distribution['npx'] != null ||
      distribution['uvx'] != null ||
      (distribution['binary'] as Map?)?[AcpRegistry.platform] != null;
}

/// How an agent is started.
typedef AcpLaunch = ({String command, List<String> args});

/// The Agent Client Protocol's public registry of agents
/// (agentclientprotocol.com/registry), and installing one from it.
class AcpRegistry {
  static const url = 'https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json';

  /// This computer as the registry names platforms: darwin-aarch64, and so on.
  static String get platform {
    final os = Platform.isMacOS
        ? 'darwin'
        : Platform.isWindows
        ? 'windows'
        : 'linux';
    final arm = switch (Abi.current()) {
      Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => true,
      _ => false,
    };
    return '$os-${arm ? 'aarch64' : 'x86_64'}';
  }

  List<AcpListing>? _cached;

  /// The agents listed, those that run here first; null when the registry
  /// could not be reached.
  Future<List<AcpListing>?> list() async {
    if (_cached case final c?) return c;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'Helmy');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      return _cached = parse(json.cast());
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static List<AcpListing> parse(Map<String, Object?> json) => [
    for (final a in (json['agents'] as List? ?? const []).whereType<Map>())
      AcpListing.fromJson(a.cast()),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Installs [a] under [root] (its own folder, by id and version), and
  /// says how to start it. An npm or Python package needs nothing
  /// installed: npx or uvx fetches it on first start. A download is checked
  /// against the registry's checksum before it is opened.
  ///
  /// [progress] hears how much of a download has come (bytes, and the
  /// whole when known, else 0). A download that sends nothing for [idle]
  /// is given up, rather than left waiting for ever.
  static Future<AcpLaunch> install(
    AcpListing a, {
    required String root,
    void Function(int got, int total)? progress,
    Duration idle = const Duration(seconds: 60),
    CliLocator? locator,
  }) async {
    final d = a.distribution;
    if (d['npx'] case final Map npx) {
      return (
        command: 'npx',
        args: ['-y', '${npx['package']}', ...((npx['args'] as List?) ?? const []).map((x) => '$x')],
      );
    }
    if (d['uvx'] case final Map uvx) {
      return (
        command: 'uvx',
        args: ['${uvx['package']}', ...((uvx['args'] as List?) ?? const []).map((x) => '$x')],
      );
    }
    final bin = (d['binary'] as Map?)?[platform] as Map?;
    // Already installed on this computer (OpenCode from its own installer,
    // npm or Homebrew): that one is used, nothing downloaded, so long as
    // it has the mode Helmy talks to it in.
    if (locator != null && bin != null) {
      if (await installedAgent(bin, locator, registryId: a.id) case final there?) return there;
    }
    if (bin == null) throw AcpInstallTrouble('${a.name} has no build for this computer.');
    final dir = Directory(p.join(root, a.id, a.version));
    final cmd = '${bin['cmd']}'.replaceFirst(RegExp(r'^\./'), '');
    final target = File(p.join(dir.path, p.joinAll(cmd.split('/'))));
    final args = [for (final x in (bin['args'] as List? ?? const [])) '$x'];
    if (target.existsSync()) return (command: target.path, args: args);
    await dir.create(recursive: true);
    final archive = '${bin['archive']}';
    final download = File(p.join(dir.path, '.download'));
    try {
      final client = HttpClient();
      try {
        client.connectionTimeout = const Duration(seconds: 20);
        final host = Uri.parse(archive).host;
        final HttpClientResponse res;
        try {
          final req = await client.getUrl(Uri.parse(archive));
          req.headers.set('User-Agent', 'Helmy');
          res = await req.close().timeout(idle);
        } on Object {
          throw AcpInstallTrouble(
            "${a.name}'s download at $host didn't answer. Check the internet connection (a "
            'network that blocks $host blocks it too) and try again.',
          );
        }
        if (res.statusCode != 200) {
          throw AcpInstallTrouble(
            "${a.name}'s download at $host failed (${res.statusCode}). Try again in a while.",
          );
        }
        final sink = download.openWrite();
        var got = 0;
        try {
          await for (final chunk in res.timeout(idle)) {
            sink.add(chunk);
            got += chunk.length;
            progress?.call(got, res.contentLength < 0 ? 0 : res.contentLength);
          }
        } on TimeoutException {
          throw AcpInstallTrouble(
            "${a.name}'s download stopped coming, after ${got ~/ 1000000} MB. Check the internet "
            'connection and try again.',
          );
        } on IOException {
          throw AcpInstallTrouble(
            "${a.name}'s download was cut off, after ${got ~/ 1000000} MB. Try again.",
          );
        } finally {
          await sink.close();
        }
      } finally {
        client.close(force: true);
      }
      if (bin['sha256'] case final String expected) {
        final hash = await Sha256().hash(await download.readAsBytes());
        final got = [for (final b in hash.bytes) b.toRadixString(16).padLeft(2, '0')].join();
        if (got != expected.toLowerCase()) {
          throw AcpInstallTrouble(
            "${a.name}'s download did not match the registry's checksum, so it wasn't opened. "
            'Try again.',
          );
        }
      }
      final name = archive.toLowerCase();
      final ProcessResult r;
      if (name.endsWith('.zip') ||
          name.endsWith('.tar.gz') ||
          name.endsWith('.tgz') ||
          name.endsWith('.tar.xz')) {
        final (exe, args) = unpackCommand(name, download.path, dir.path);
        try {
          r = await Process.run(exe, args);
        } on ProcessException {
          throw AcpInstallTrouble(
            "${a.name} came, but this computer has no $exe to unpack it with.",
          );
        }
      } else {
        await download.rename(target.path);
        r = ProcessResult(0, 0, '', '');
      }
      if (r.exitCode != 0) {
        throw AcpInstallTrouble('${a.name} could not be unpacked: ${'${r.stderr}'.trim()}');
      }
      if (!target.existsSync()) throw AcpInstallTrouble('${a.name} unpacked without $cmd in it.');
      if (!Platform.isWindows) await Process.run('chmod', ['+x', target.path]);
      return (command: target.path, args: args);
    } catch (_) {
      if (dir.existsSync()) await dir.delete(recursive: true);
      rethrow;
    } finally {
      if (download.existsSync()) await download.delete();
    }
  }
}

/// Why an agent could not be installed, in words to show.
class AcpInstallTrouble implements Exception {
  const AcpInstallTrouble(this.message);
  final String message;
  @override
  String toString() => message;
}

/// How an archive [name] at [file] is unpacked into [dir] here: ditto on a
/// Mac (keeping an app's signature whole), Windows' own tar (which reads a
/// zip too, since Windows 10), unzip or tar on Linux.
(String, List<String>) unpackCommand(String name, String file, String dir, {String? os}) {
  final here = os ?? Platform.operatingSystem;
  final zip = name.toLowerCase().endsWith('.zip');
  return switch (here) {
    'macos' when zip => ('/usr/bin/ditto', ['-x', '-k', file, dir]),
    'windows' => (
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\tar.exe',
      ['-xf', file, '-C', dir],
    ),
    _ when zip => ('unzip', ['-oq', file, '-d', dir]),
    _ => ('tar', ['-xf', file, '-C', dir]),
  };
}

/// The agent [bin] describes, already installed on this computer: its
/// command found where programs are, or inside its desktop app (OpenCode
/// Desktop's opencode-cli), so long as it has the mode Helmy starts it in
/// (OpenCode's `acp`; an old one without it is passed over). Null when it
/// is not there.
Future<AcpLaunch?> installedAgent(
  Map<dynamic, dynamic> bin,
  CliLocator locator, {
  String? registryId,
}) async {
  final cmd = '${bin['cmd']}'.split(RegExp(r'[/\\]')).last.replaceFirst(RegExp(r'\.exe$'), '');
  final args = [for (final x in (bin['args'] as List? ?? const [])) '$x'];
  final candidates = [
    ?await locator.find(cmd),
    if (registryId != null)
      for (final p in desktopPrograms(registryId))
        if (File(p).existsSync()) p,
  ];
  for (final path in candidates) {
    if (await answersIn(path, args)) return (command: path, args: args);
  }
  return null;
}

/// Whether the program at [path] can be started as [args] say: its help
/// names the mode Helmy starts it in (args' first, `acp` for OpenCode).
/// With no args, being there is enough.
Future<bool> answersIn(String path, List<String> args) async {
  if (!File(path).existsSync()) return false;
  if (args.isEmpty) return true;
  try {
    final r = await Process.run(
      path,
      ['--help'],
      runInShell: Platform.isWindows && AcpRpc.runsInShell(path),
    ).timeout(const Duration(seconds: 15));
    final help = '${r.stdout}\n${r.stderr}';
    return RegExp('(^|\\s)${RegExp.escape(args.first)}(\\s|\$)', multiLine: true).hasMatch(help);
  } on Object {
    return false;
  }
}

/// The desktop apps that carry an agent's command-line program, by the
/// agent's registry id: its name, its app id, and the program inside.
const desktopApps = {'opencode': (app: 'OpenCode', id: 'ai.opencode.desktop', cli: 'opencode-cli')};

/// Where agent [registryId]'s desktop app keeps its command-line program on
/// this system, as its installers put it: in the app's resources, in
/// Applications on a Mac, in the person's own Programs on Windows (named by
/// its app id, or as older versions named it), and in /opt on Linux.
List<String> desktopPrograms(String registryId, {String? os, Map<String, String>? env}) {
  final d = desktopApps[registryId];
  if (d == null) return const [];
  final e = env ?? Platform.environment;
  final here = os ?? Platform.operatingSystem;
  final ctx = here == 'windows' ? p.windows : p.posix;
  final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
  return switch (here) {
    'macos' => [
      for (final apps in ['/Applications', ctx.join(home, 'Applications')])
        ctx.join(apps, '${d.app}.app', 'Contents', 'Resources', d.cli),
    ],
    'windows' => [
      if (e['LOCALAPPDATA'] case final local?)
        for (final dir in [d.id, '@${d.app.toLowerCase()}desktop', d.app])
          ctx.join(local, 'Programs', dir, 'resources', '${d.cli}.exe'),
      if (e['ProgramFiles'] case final pf?) ctx.join(pf, d.app, 'resources', '${d.cli}.exe'),
    ],
    _ => [ctx.join('/opt', d.app, 'resources', d.cli)],
  };
}

/// The program to use when the person picked [picked] for agent
/// [registryId]: itself, or, when it is the agent's desktop app
/// (OpenCode.app, or OpenCode.exe in its folder), the command-line program
/// inside it.
String programIn(String picked, String registryId, {String? os}) {
  final d = desktopApps[registryId];
  if (d == null) return picked;
  final here = os ?? Platform.operatingSystem;
  final ctx = here == 'windows' ? p.windows : p.posix;
  final name = ctx.basename(picked).toLowerCase();
  if (name == d.cli || name.startsWith('${d.cli}.')) return picked;
  final inside = name.endsWith('.app')
      ? ctx.join(picked, 'Contents', 'Resources', d.cli)
      : ctx.join(ctx.dirname(picked), 'resources', here == 'windows' ? '${d.cli}.exe' : d.cli);
  return File(inside).existsSync() ? inside : picked;
}
