import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/acp/acp_registry.dart';

/// Installing an agent from the registry (OpenCode, on the first run): its
/// download shows how far it has come, a stalled one is given up and said
/// so, and each system unpacks it with what it has.
void main() {
  installedTests();
  late Directory root;
  late HttpServer server;
  late File archive;
  var stall = false;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('acp');
    // A real archive holding the agent's program.
    final src = Directory('${root.path}/src')..createSync();
    File('${src.path}/agent').writeAsStringSync('#!/bin/sh\necho hi\n');
    archive = File('${root.path}/agent.tar.gz');
    await Process.run('tar', ['-czf', archive.path, '-C', src.path, 'agent']);
    stall = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final bytes = archive.readAsBytesSync();
      r.response.contentLength = bytes.length;
      if (stall) {
        r.response.add(bytes.sublist(0, 10));
        await r.response.flush();
        return; // and nothing more
      }
      r.response.add(bytes);
      await r.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });

  AcpListing listing() => AcpListing(
    id: 'agent',
    name: 'Agent',
    version: '1.0',
    distribution: {
      'binary': {
        AcpRegistry.platform: {
          'archive': 'http://127.0.0.1:${server.port}/agent.tar.gz',
          'cmd': './agent',
          'args': ['acp'],
        },
      },
    },
  );

  test('downloaded, unpacked, and how far it came heard on the way', () async {
    final heard = <(int, int)>[];
    final launch = await AcpRegistry.install(
      listing(),
      root: '${root.path}/agents',
      progress: (got, total) => heard.add((got, total)),
    );
    expect(File(launch.command).existsSync(), isTrue);
    expect(launch.args, ['acp']);
    final size = archive.lengthSync();
    expect(heard.last, (size, size));
  });

  test('a download that stops coming is given up, and says so', () async {
    stall = true;
    await expectLater(
      AcpRegistry.install(
        listing(),
        root: '${root.path}/agents',
        idle: const Duration(milliseconds: 300),
      ),
      throwsA(
        isA<AcpInstallTrouble>().having((e) => e.message, 'message', contains('stopped coming')),
      ),
    );
    expect(Directory('${root.path}/agents/agent/1.0').existsSync(), isFalse, reason: 'cleaned up');
  });

  test('a download that does not answer names where it is from', () async {
    final l = listing();
    final bin = (l.distribution['binary']! as Map)[AcpRegistry.platform] as Map;
    bin['archive'] = 'http://127.0.0.1:1/agent.tar.gz';
    await expectLater(
      AcpRegistry.install(l, root: '${root.path}/agents'),
      throwsA(isA<AcpInstallTrouble>().having((e) => e.message, 'message', contains('127.0.0.1'))),
    );
  });

  test('each system unpacks with what it has', () {
    expect(unpackCommand('a.zip', 'f', 'd', os: 'macos').$1, '/usr/bin/ditto');
    expect(unpackCommand('a.zip', 'f', 'd', os: 'windows').$1, endsWith(r'\System32\tar.exe'));
    expect(unpackCommand('a.zip', 'f', 'd', os: 'windows').$2, ['-xf', 'f', '-C', 'd']);
    expect(unpackCommand('a.tar.gz', 'f', 'd', os: 'linux').$1, 'tar');
    expect(unpackCommand('a.zip', 'f', 'd', os: 'linux').$1, 'unzip');
  });
}

class _Locator extends CliLocator {
  _Locator(this.there);
  final Map<String, String> there;
  @override
  Future<String?> find(String name) async => there[name];
}

void installedTests() {
  test('an agent already installed is used when it has the mode Helmy needs', () async {
    final dir = Directory.systemTemp.createTempSync('installed');
    addTearDown(() => dir.deleteSync(recursive: true));
    File script(String name, String help) {
      final f = File('${dir.path}/$name')..writeAsStringSync('#!/bin/sh\necho "$help"\n');
      Process.runSync('chmod', ['+x', f.path]);
      return f;
    }

    final fresh = script('opencode', 'Commands:\n  acp    Start ACP server\n  run');
    final old = script('opencode-old', 'Commands:\n  run\n  serve');
    const bin = {
      'cmd': './opencode.exe',
      'args': ['acp'],
    };
    final got = await installedAgent(bin, _Locator({'opencode': fresh.path}));
    expect((got?.command, got?.args.join(' ')), (fresh.path, 'acp'));
    expect(await installedAgent(bin, _Locator({'opencode': old.path})), isNull, reason: 'no acp');
    expect(await installedAgent(bin, _Locator({})), isNull, reason: 'not installed');
  }, skip: Platform.isWindows ? 'a shell script stands in for it' : null);
}
