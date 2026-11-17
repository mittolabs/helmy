import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../../cli_locator.dart';

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
      if (await installedAgent(bin, locator) case final there?) return there;
    }
    if (bin == null) throw AcpInstallTrouble('${a.name} has no build for this computer.');
    final dir = Directory('$root/${a.id}/${a.version}');
    final cmd = '${bin['cmd']}'.replaceFirst(RegExp(r'^\./'), '');
    final target = File('${dir.path}/$cmd');
    final args = [for (final x in (bin['args'] as List? ?? const [])) '$x'];
    if (target.existsSync()) return (command: target.path, args: args);
    await dir.create(recursive: true);
    final archive = '${bin['archive']}';
    final download = File('${dir.path}/.download');
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
/// command found where programs are, and its help naming the mode Helmy
/// starts it in (OpenCode's `acp`; an old one without it is passed over).
/// Null when it is not there.
Future<AcpLaunch?> installedAgent(Map<dynamic, dynamic> bin, CliLocator locator) async {
  final cmd = '${bin['cmd']}'.split(RegExp(r'[/\\]')).last.replaceFirst(RegExp(r'\.exe$'), '');
  final args = [for (final x in (bin['args'] as List? ?? const [])) '$x'];
  final path = await locator.find(cmd);
  if (path == null) return null;
  if (args.isNotEmpty) {
    try {
      final r = await Process.run(
        path,
        ['--help'],
        runInShell: Platform.isWindows && path.toLowerCase().endsWith('.cmd'),
      ).timeout(const Duration(seconds: 15));
      final help = '${r.stdout}\n${r.stderr}';
      if (!RegExp('(^|\\s)${RegExp.escape(args.first)}(\\s|\$)', multiLine: true).hasMatch(help)) {
        return null;
      }
    } on Object {
      return null;
    }
  }
  return (command: path, args: args);
}
