import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/connection_installer.dart';

/// A server on this computer that sends [body] in pieces, or stops after
/// [stopAfter] bytes and goes quiet (a stalled download).
Future<HttpServer> serve(List<int> body, {int? stopAfter, bool lieAboutLength = false}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final res = req.response;
    res.contentLength = lieAboutLength ? body.length * 2 : body.length;
    final send = stopAfter == null ? body : body.sublist(0, stopAfter);
    for (var i = 0; i < send.length; i += 100000) {
      res.add(send.sublist(i, (i + 100000).clamp(0, send.length)));
      await res.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (stopAfter != null) {
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    try {
      await res.close();
    } on HttpException {
      // Sent less than it said: what a cut-off download looks like.
    }
  });
  return server;
}

Future<String> hex(List<int> bytes) async =>
    [for (final b in (await Sha256().hash(bytes)).bytes) b.toRadixString(16).padLeft(2, '0')]
        .join();

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('installer-test-'));
  tearDown(() async => dir.delete(recursive: true));

  final body = List<int>.generate(1500000, (i) => i % 251);

  test('a download is checked against its checksum and says how far it has come', () async {
    final server = await serve(body);
    addTearDown(server.close);
    final to = File('${dir.path}/claude');
    final heard = <(int, int)>[];
    await ConnectionInstaller.download(
      Uri.parse('http://127.0.0.1:${server.port}/claude'),
      to,
      name: 'Claude Code',
      sha256: await hex(body),
      progress: (got, total) => heard.add((got, total)),
    );
    expect(to.lengthSync(), body.length);
    expect(heard.length, greaterThan(5), reason: 'heard as it comes, not once at the end');
    expect(heard.last, (body.length, body.length));
    expect(ConnectionInstaller.downloading(heard[3].$1, heard[3].$2).done, inExclusiveRange(0, 1));
  });

  test('one that does not match its checksum is not kept', () async {
    final server = await serve(body);
    addTearDown(server.close);
    final to = File('${dir.path}/claude');
    await expectLater(
      ConnectionInstaller.download(
        Uri.parse('http://127.0.0.1:${server.port}/claude'),
        to,
        name: 'Claude Code',
        sha256: 'ab' * 32,
      ),
      throwsA(isA<InstallTrouble>().having((e) => e.message, 'message', contains("didn't match"))),
    );
    expect(to.existsSync(), isFalse);
  });

  test('one that goes quiet is given up, with how much had come', () async {
    final server = await serve(body, stopAfter: 1200000);
    addTearDown(() => server.close(force: true));
    final to = File('${dir.path}/ollama.zip');
    await expectLater(
      ConnectionInstaller.download(
        Uri.parse('http://127.0.0.1:${server.port}/x'),
        to,
        name: 'Ollama',
        idle: const Duration(seconds: 1),
      ),
      throwsA(
        isA<InstallTrouble>().having(
          (e) => e.message,
          'message',
          "Ollama's download stopped coming, after 1 MB. Check the internet connection and try "
              'again.',
        ),
      ),
    );
    expect(to.existsSync(), isFalse);
  });

  test('one cut off before its whole length is not kept', () async {
    final server = await serve(body, lieAboutLength: true);
    addTearDown(() => server.close(force: true));
    final to = File('${dir.path}/codex');
    await expectLater(
      ConnectionInstaller.download(
        Uri.parse('http://127.0.0.1:${server.port}/x'),
        to,
        name: 'Codex',
      ),
      throwsA(isA<InstallTrouble>().having((e) => e.message, 'message', contains('cut off'))),
    );
    expect(to.existsSync(), isFalse);
  });

  test('a host that does not answer says which, and what to check', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    await expectLater(
      ConnectionInstaller.download(
        Uri.parse('http://127.0.0.1:$port/x'),
        File('${dir.path}/x'),
        name: 'Codex',
      ),
      throwsA(
        isA<InstallTrouble>().having(
          (e) => e.message,
          'message',
          allOf(contains("didn't answer"), contains('127.0.0.1')),
        ),
      ),
    );
  });

  group('an installer it runs', () {
    test('is heard line by line, a progress meter as it moves', () async {
      final lines = <String>[];
      final code = await ConnectionInstaller.watch(
        '/bin/sh',
        ['-c', r'echo "==> Downloading Codex CLI"; printf "## 10.0%%\r### 55.5%%\r"; echo done'],
        environment: Platform.environment,
        stall: const Duration(seconds: 30),
        name: 'Codex',
        onLine: lines.add,
      );
      expect(code, 0);
      expect(lines, ['==> Downloading Codex CLI', '## 10.0%', '### 55.5%', 'done']);
    }, skip: Platform.isWindows);

    test('one that sits still is stopped, and says so', () async {
      final started = DateTime.now();
      await expectLater(
        ConnectionInstaller.watch(
          '/bin/sh',
          ['-c', 'echo starting; sleep 30'],
          environment: Platform.environment,
          stall: const Duration(seconds: 2),
          name: "Codex's installer",
        ),
        throwsA(
          isA<InstallTrouble>().having(
            (e) => e.message,
            'message',
            "Codex's installer sat still for 2 seconds with nothing to show, so Helmy stopped "
                'it. Check the internet connection and try again.',
          ),
        ),
      );
      expect(DateTime.now().difference(started).inSeconds, lessThan(10));
    }, skip: Platform.isWindows);

    test('one whose download is growing is not still, though it says nothing', () async {
      final file = File('${dir.path}/landing');
      var size = 0;
      final grow = Timer.periodic(const Duration(milliseconds: 300), (_) {
        size += 1000;
        file.writeAsBytesSync(List.filled(size, 0));
      });
      addTearDown(grow.cancel);
      final code = await ConnectionInstaller.watch(
        '/bin/sh',
        ['-c', 'sleep 4'],
        environment: Platform.environment,
        stall: const Duration(seconds: 2),
        name: 'Codex',
        growth: () => file.existsSync() ? file.lengthSync() : 0,
      );
      expect(code, 0);
    }, skip: Platform.isWindows);

    test('one that is not there says it could not start', () async {
      await expectLater(
        ConnectionInstaller.watch(
          '${dir.path}/nothing-here',
          const [],
          environment: Platform.environment,
          stall: const Duration(seconds: 5),
          name: 'Claude Code',
        ),
        throwsA(isA<InstallTrouble>()),
      );
    });
  });

  test("an installer's download is found where mktemp put it, if it is new", () async {
    final since = DateTime.now().subtract(const Duration(seconds: 1));
    final mine = await Directory('${dir.path}/tmp').create();
    final system = await Directory('${dir.path}/system').create();
    const name = 'codex-package-aarch64-apple-darwin.tar.gz';
    const names = {name, 'codex-package_SHA256SUMS'};
    expect(ConnectionInstaller.landedIn([mine, system], names, since), 0);
    // Left by an earlier install: not this one.
    final old = File('${system.path}/tmp.OLD/$name')..createSync(recursive: true);
    old.writeAsBytesSync(List.filled(500, 0));
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    expect(ConnectionInstaller.landedIn([mine, system], names, since), 0);
    // Someone else's download, in a folder of its own: not this one.
    File('${system.path}/tmp.OTHER/movie.mp4')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(9000, 0));
    expect(ConnectionInstaller.landedIn([mine, system], names, since), 0);
    // This one's, in the person's own temporary folder (a Mac), its
    // archive under the checksum list's name, as Codex's installer has.
    File('${system.path}/tmp.NEW/codex-package_SHA256SUMS')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(1200, 0));
    expect(ConnectionInstaller.landedIn([mine, system], names, since), 1200);
  });

  test('each system is named as its maker names it', () {
    expect(ConnectionInstaller.claudePlatform(os: 'macos', arm: true), 'darwin-arm64');
    expect(ConnectionInstaller.claudePlatform(os: 'windows', arm: false), 'win32-x64');
    expect(ConnectionInstaller.claudePlatform(os: 'linux', arm: true), 'linux-arm64');
    expect(
      ConnectionInstaller.claudePlatform(os: 'linux', arm: false, musl: true),
      'linux-x64-musl',
    );
    expect(ConnectionInstaller.codexTarget(os: 'macos', arm: true), 'aarch64-apple-darwin');
    expect(ConnectionInstaller.codexTarget(os: 'windows', arm: true), 'aarch64-pc-windows-msvc');
    expect(ConnectionInstaller.codexTarget(os: 'linux', arm: false), 'x86_64-unknown-linux-musl');
  });

  test("an installer's lines become steps, in Helmy's words", () {
    expect(ConnectionInstaller.codexStep('==> Downloading Codex CLI'), 'Downloading…');
    expect(
      ConnectionInstaller.codexStep('==> Installing standalone package to /x/releases/0.170.0'),
      'Setting it up…',
    );
    expect(ConnectionInstaller.codexStep('==> Resolved version: 0.170.0'), isNull);
    expect(ConnectionInstaller.codexStep('some other output'), isNull);

    final pct = ConnectionInstaller.ollamaLinuxStep('######################       42.3%');
    expect(pct?.doing, 'Downloading, 42%…');
    expect(pct?.done, closeTo(0.423, 0.0001));
    expect(
      ConnectionInstaller.ollamaLinuxStep('>>> Downloading ollama-linux-amd64.tar.zst')?.doing,
      'Downloading…',
    );
    expect(
      ConnectionInstaller.ollamaLinuxStep('>>> Installing ollama to /usr/local')?.doing,
      'Setting it up…',
    );
    expect(
      ConnectionInstaller.ollamaLinuxStep('>>> Enabling and starting ollama service...')?.doing,
      'Starting it…',
    );
    expect(ConnectionInstaller.ollamaLinuxStep('WARNING: something'), isNull);
  });

  test("Ollama's checksums are read by file name", () {
    final sums = ConnectionInstaller.parseSums(
      '${'a' * 64}  ./Ollama-darwin.zip\n${'B' * 64}  ./OllamaSetup.exe\nnot a line\n',
    );
    expect(sums, {'Ollama-darwin.zip': 'a' * 64, 'OllamaSetup.exe': 'b' * 64});
  });

  test('a download says megabytes, of how many when known', () {
    expect(
      ConnectionInstaller.downloading(120000000, 354000000).doing,
      'Downloading, 120 of 354 MB…',
    );
    expect(ConnectionInstaller.downloading(5000000, 0), (doing: 'Downloading, 5 MB…', done: null));
  });
}
