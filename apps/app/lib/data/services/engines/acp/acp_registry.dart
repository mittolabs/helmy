import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:cryptography/cryptography.dart';

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
  static Future<AcpLaunch> install(AcpListing a, {required String root}) async {
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
    if (bin == null) throw StateError('${a.name} has no build for this computer.');
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
        final req = await client.getUrl(Uri.parse(archive));
        req.headers.set('User-Agent', 'Helmy');
        final res = await req.close();
        if (res.statusCode != 200) throw HttpException('download failed (${res.statusCode})');
        await res.pipe(download.openWrite());
      } finally {
        client.close(force: true);
      }
      if (bin['sha256'] case final String expected) {
        final hash = await Sha256().hash(await download.readAsBytes());
        final got = [for (final b in hash.bytes) b.toRadixString(16).padLeft(2, '0')].join();
        if (got != expected.toLowerCase()) {
          throw StateError("${a.name}'s download did not match the registry's checksum.");
        }
      }
      final name = archive.toLowerCase();
      final ProcessResult r;
      if (name.endsWith('.zip')) {
        r = await Process.run('/usr/bin/ditto', ['-x', '-k', download.path, dir.path]);
      } else if (name.endsWith('.tar.gz') || name.endsWith('.tgz') || name.endsWith('.tar.xz')) {
        r = await Process.run('/usr/bin/tar', ['-xf', download.path, '-C', dir.path]);
      } else {
        await download.rename(target.path);
        r = ProcessResult(0, 0, '', '');
      }
      if (r.exitCode != 0) throw StateError('${a.name} could not be unpacked: ${r.stderr}');
      if (!target.existsSync()) throw StateError('${a.name} unpacked without $cmd in it.');
      await Process.run('/bin/chmod', ['+x', target.path]);
      return (command: target.path, args: args);
    } catch (_) {
      if (dir.existsSync()) await dir.delete(recursive: true);
      rethrow;
    } finally {
      if (download.existsSync()) await download.delete();
    }
  }
}
