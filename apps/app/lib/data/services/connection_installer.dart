import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../../utils/platform.dart';
import '../../utils/paths.dart';
import 'cli_locator.dart';
import 'engines/ollama/ollama_doctor.dart';

/// What an install is doing now, in words to show, and how far along it is
/// (0 to 1) when that is known.
typedef InstallStep = ({String doing, double? done});

/// Why a connection did not install, in Helmy's words, with what fixes it.
class InstallTrouble implements Exception {
  const InstallTrouble(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Installs Claude Code, Codex and Ollama the way each maker does, with how
/// far along it is shown as it goes and a limit on how long it may sit
/// still, so it never hangs behind a spinner:
///
/// - Claude Code: its maker's steps, done here on every system: the newest
///   build downloaded from downloads.claude.ai, checked against its
///   manifest's checksum, then its own `install` sets it up.
/// - Codex: its maker's installer from its release (install.sh, or
///   install.ps1 on Windows), whose steps are shown and whose download is
///   watched as it lands.
/// - Ollama: on a Mac its app, checked and put in Applications; on Windows
///   its setup, checked and run silently, as its own script does; on Linux
///   its own script, which needs an administrator, so the system asks for
///   the password (pkexec).
class ConnectionInstaller {
  ConnectionInstaller(this._locator);
  final CliLocator _locator;

  static const claudeBase = 'https://downloads.claude.ai/claude-code-releases';
  static const codexLatest = 'https://github.com/openai/codex/releases/latest/download';
  static const ollamaLatest = 'https://github.com/ollama/ollama/releases/latest/download';

  /// Installs [id] ('claude', 'codex' or 'ollama'), saying each step to
  /// [step]. Throws [InstallTrouble] when it could not.
  Future<void> install(String id, void Function(InstallStep) step) async {
    final work = await Directory.systemTemp.createTemp('helmy-install-');
    try {
      switch (id) {
        case 'claude':
          await _claude(work, step);
        case 'codex':
          await _codex(work, step);
        case 'ollama':
          await _ollama(work, step);
        default:
          throw InstallTrouble("Helmy doesn't know how to install $id.");
      }
    } finally {
      try {
        await work.delete(recursive: true);
      } on Object {
        // A file still held open (Windows) goes with the system's cleanup.
      }
    }
  }

  // Claude Code.

  /// This computer as Claude Code's manifest names it: darwin-arm64,
  /// linux-x64-musl, win32-x64.
  static String claudePlatform({String? os, bool? arm, bool musl = false}) {
    final here = os ?? Platform.operatingSystem;
    final a = (arm ?? _arm) ? 'arm64' : 'x64';
    return switch (here) {
      'macos' => 'darwin-$a',
      'windows' => 'win32-$a',
      _ => musl ? 'linux-$a-musl' : 'linux-$a',
    };
  }

  Future<void> _claude(Directory work, void Function(InstallStep) step) async {
    step((doing: 'Finding the newest Claude Code…', done: null));
    const host = 'downloads.claude.ai';
    final version = (await _text(Uri.parse('$claudeBase/latest'), host)).trim();
    if (!RegExp(r'^\d+\.\d+\.\d+').hasMatch(version)) {
      throw const InstallTrouble(
        "Claude Code's download ($host) didn't answer with a version. It may not be offered "
        'where you are (anthropic.com/supported-countries), or this network blocks it.',
      );
    }
    final manifest = jsonDecode(await _text(Uri.parse('$claudeBase/$version/manifest.json'), host));
    final platforms = (manifest as Map)['platforms'] as Map? ?? const {};
    final platform = claudePlatform(arm: await _armMac(), musl: await _musl());
    final build = platforms[platform] as Map?;
    if (build == null) throw const InstallTrouble('Claude Code has no build for this computer.');
    final file = '${build['binary'] ?? (Platform.isWindows ? 'claude.exe' : 'claude')}';
    final bin = File('${work.path}${Platform.pathSeparator}$file');
    await download(
      Uri.parse('$claudeBase/$version/$platform/$file'),
      bin,
      name: 'Claude Code',
      sha256: '${build['checksum'] ?? ''}',
      progress: (got, total) => step(downloading(got, total)),
    );
    if (!Platform.isWindows) await Process.run('chmod', ['+x', bin.path]);
    // Its own setup: where it lives, the command, updates. It downloads
    // nothing more, so a few minutes still is stuck.
    step((doing: 'Setting it up…', done: null));
    final code = await watch(
      bin.path,
      ['install'],
      environment: await _locator.environment(),
      stall: const Duration(minutes: 3),
      name: 'Claude Code',
    );
    if (code != 0) {
      throw InstallTrouble(
        code == 137 && Platform.isLinux
            ? 'Claude Code downloaded, but this computer ran out of memory setting it up. It '
                  'needs about 512 MB free: close something, then try again.'
            : "Claude Code downloaded, but its setup didn't finish (it stopped with $code). "
                  'Try again.',
      );
    }
  }

  // Codex.

  /// This computer as Codex's releases name it: aarch64-apple-darwin,
  /// x86_64-unknown-linux-musl, x86_64-pc-windows-msvc.
  static String codexTarget({String? os, bool? arm}) {
    final cpu = (arm ?? _arm) ? 'aarch64' : 'x86_64';
    return switch (os ?? Platform.operatingSystem) {
      'macos' => '$cpu-apple-darwin',
      'windows' => '$cpu-pc-windows-msvc',
      _ => '$cpu-unknown-linux-musl',
    };
  }

  /// What a line of Codex's installer means for the step shown; null for a
  /// line that changes nothing.
  static String? codexStep(String line) {
    final l = line.toLowerCase();
    if (!l.startsWith('==>')) return null;
    if (l.contains('download')) return 'Downloading…';
    if (l.contains('installing standalone') || l.contains('extract')) return 'Setting it up…';
    if (l.contains('path')) return 'Adding it to the command line…';
    return null;
  }

  Future<void> _codex(Directory work, void Function(InstallStep) step) async {
    step((doing: "Getting Codex's installer…", done: null));
    final windows = Platform.isWindows;
    final script = File('${work.path}${Platform.pathSeparator}install.${windows ? 'ps1' : 'sh'}');
    await download(
      Uri.parse('$codexLatest/install.${windows ? 'ps1' : 'sh'}'),
      script,
      name: "Codex's installer",
    );
    // Its download lands in a folder of its own in the temporary folder
    // it is given (TEMP on Windows, TMPDIR on Linux), or, on a Mac, whose
    // mktemp ignores TMPDIR, in the person's own: both are watched, for a
    // file that came after it started.
    final temp = await Directory('${work.path}${Platform.pathSeparator}tmp').create();
    final asset = 'codex-package-${codexTarget(arm: await _armMac())}.tar.gz';
    final total = await _githubAssetSize('openai/codex', asset);
    final since = DateTime.now().subtract(const Duration(seconds: 2));
    final roots = [temp, Directory.systemTemp, ?await _macUserTemp()];
    // By the folder it made, not the name: its archive has been written
    // under its checksum list's name (codex-package_SHA256SUMS).
    int landed() => landedIn(roots, {asset, 'codex-package_SHA256SUMS'}, since);
    var doing = "Starting Codex's installer…";
    var lastGot = -1;
    step((doing: doing, done: null));
    final env = {
      ...await _locator.environment(),
      'CODEX_NON_INTERACTIVE': '1',
      if (windows) ...{'TEMP': temp.path, 'TMP': temp.path} else 'TMPDIR': temp.path,
    };
    final code = await watch(
      windows ? 'powershell' : '/bin/sh',
      windows
          ? ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script.path]
          : [script.path],
      environment: env,
      stall: const Duration(seconds: 90),
      name: "Codex's installer",
      growth: landed,
      onLine: (line) {
        if (codexStep(line) case final s?) {
          doing = s;
          step((doing: doing, done: null));
        }
      },
      tick: () {
        final got = landed();
        if (got <= 0 || got == lastGot || doing != 'Downloading…') return;
        lastGot = got;
        step(downloading(got, total ?? 0));
      },
    );
    if (code != 0) {
      throw InstallTrouble(
        "Codex's installer didn't finish (it stopped with $code). Check the internet "
        'connection and try again.',
      );
    }
  }

  // Ollama.

  Future<void> _ollama(Directory work, void Function(InstallStep) step) async {
    if (Platform.isMacOS) return _ollamaMac(work, step);
    if (Platform.isWindows) return _ollamaWindows(work, step);
    return _ollamaLinux(work, step);
  }

  /// The checksums Ollama publishes with its newest release, by file name.
  Future<Map<String, String>> _ollamaSums() async {
    final text = await _text(Uri.parse('$ollamaLatest/sha256sum.txt'), 'github.com');
    return parseSums(text);
  }

  /// A sha256sum list ("hash  ./name" per line) by file name.
  static Map<String, String> parseSums(String text) => {
    for (final line in const LineSplitter().convert(text))
      if (RegExp(r'^([0-9a-fA-F]{64})\s+\*?(?:\./)?(\S+)$').firstMatch(line.trim()) case final m?)
        m[2]!: m[1]!.toLowerCase(),
  };

  Future<void> _ollamaMac(Directory work, void Function(InstallStep) step) async {
    step((doing: 'Finding the newest Ollama…', done: null));
    final sums = await _ollamaSums();
    const name = 'Ollama-darwin.zip';
    final zip = File('${work.path}/$name');
    await download(
      Uri.parse('$ollamaLatest/$name'),
      zip,
      name: 'Ollama',
      sha256: sums[name] ?? '',
      progress: (got, total) => step(downloading(got, total)),
    );
    step((doing: 'Putting it in Applications…', done: null));
    final out = await Directory('${work.path}/app').create();
    final unzip = await Process.run('/usr/bin/ditto', ['-x', '-k', zip.path, out.path]);
    final app = Directory('${out.path}/Ollama.app');
    if (unzip.exitCode != 0 || !app.existsSync()) {
      throw const InstallTrouble("Ollama downloaded, but it didn't unpack. Try again.");
    }
    // Applications when it may be written to, as for most people; else the
    // person's own Applications folder.
    final shared = Directory('/Applications');
    final to = _writable(shared) ? shared.path : '$homeDir/Applications';
    await Directory(to).create(recursive: true);
    final moved = await Process.run('/bin/mv', [app.path, '$to/Ollama.app']);
    if (moved.exitCode != 0) {
      throw InstallTrouble("Ollama downloaded, but it couldn't be put in $to. Try again.");
    }
    step((doing: 'Starting it…', done: null));
    await Process.run('/usr/bin/open', ['-a', '$to/Ollama.app', '--args', 'hidden']);
    await _answers();
  }

  Future<void> _ollamaWindows(Directory work, void Function(InstallStep) step) async {
    step((doing: 'Finding the newest Ollama…', done: null));
    final sums = await _ollamaSums();
    const name = 'OllamaSetup.exe';
    final setup = File('${work.path}\\$name');
    await download(
      Uri.parse('$ollamaLatest/$name'),
      setup,
      name: 'Ollama',
      sha256: sums[name] ?? '',
      progress: (got, total) => step(downloading(got, total)),
    );
    // Its setup, as its own script runs it: silent, for this person only,
    // no administrator needed. It says nothing as it goes, so it is given
    // a while rather than watched.
    step((doing: 'Setting it up, a minute or two…', done: null));
    final ProcessResult r;
    try {
      r = await Process.run(setup.path, const [
        '/VERYSILENT',
        '/NORESTART',
        '/SUPPRESSMSGBOXES',
      ]).timeout(const Duration(minutes: 10));
    } on TimeoutException {
      throw const InstallTrouble(
        "Ollama's setup ran for 10 minutes without finishing. Restart this computer, then try "
        'again.',
      );
    }
    if (r.exitCode != 0) {
      throw InstallTrouble(
        "Ollama's setup didn't finish (it stopped with ${r.exitCode}). Try again.",
      );
    }
    _locator.forget('ollama');
    step((doing: 'Starting it…', done: null));
    await OllamaDoctor.ensure(start: true);
  }

  /// What a line of Ollama's Linux script means: the step shown, or how far
  /// its download has come (curl's "####  42.0%"); null for neither.
  static InstallStep? ollamaLinuxStep(String line) {
    final l = line.trim();
    if (RegExp(r'(\d{1,3}(?:\.\d)?)%\s*$').firstMatch(l) case final m?) {
      final pct = double.parse(m[1]!);
      return (doing: 'Downloading, ${pct.round()}%…', done: (pct / 100).clamp(0.0, 1.0));
    }
    if (!l.startsWith('>>>')) return null;
    final s = l.toLowerCase();
    if (s.contains('download')) return (doing: 'Downloading…', done: null);
    if (s.contains('cuda') || s.contains('driver')) {
      return (doing: 'Setting up the graphics card for it…', done: null);
    }
    if (s.contains('service') || s.contains('starting')) return (doing: 'Starting it…', done: null);
    if (s.contains('install') || s.contains('user') || s.contains('group')) {
      return (doing: 'Setting it up…', done: null);
    }
    return null;
  }

  Future<void> _ollamaLinux(Directory work, void Function(InstallStep) step) async {
    if (await _locator.find('zstd') == null) {
      throw const InstallTrouble(
        'Ollama comes packed with zstd, which this computer lacks. Install it (on Ubuntu or '
        'Debian: sudo apt install zstd; on Fedora: sudo dnf install zstd), then try again.',
      );
    }
    final pkexec = await _locator.find('pkexec');
    if (pkexec == null) {
      throw const InstallTrouble(
        'Ollama installs for the whole computer, which needs an administrator, and this '
        'computer has no way to ask for the password here. In a terminal, run: '
        'curl -fsSL https://ollama.com/install.sh | sh. Then try again.',
      );
    }
    step((doing: "Getting Ollama's installer…", done: null));
    final script = File('${work.path}/install.sh');
    await download(Uri.parse('$ollamaLatest/install.sh'), script, name: "Ollama's installer");
    step((doing: 'Waiting for your password…', done: null));
    final code = await watch(
      pkexec,
      ['/bin/sh', script.path],
      environment: await _locator.environment(),
      // Its graphics drivers come through the system's package manager,
      // which can say nothing for a while.
      stall: const Duration(minutes: 5),
      name: "Ollama's installer",
      onLine: (line) {
        if (ollamaLinuxStep(line) case final s?) step(s);
      },
    );
    // pkexec: 126 when the password was not given, 127 when not allowed.
    if (code == 126 || code == 127) {
      throw const InstallTrouble(
        "The password wasn't given, so Ollama wasn't installed. Try again when ready.",
      );
    }
    if (code != 0) {
      throw InstallTrouble(
        "Ollama's installer didn't finish (it stopped with $code). Check the internet "
        'connection and try again.',
      );
    }
    _locator.forget('ollama');
    await _answers();
  }

  /// Waits up to half a minute for Ollama to answer once started; it is
  /// installed either way, and starts when it is next needed.
  Future<void> _answers() async {
    for (var i = 0; i < 30; i++) {
      if (await OllamaDoctor.answers()) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  // The parts every install shares.

  /// The step a download is on: "Downloading, 120 of 354 MB…".
  static InstallStep downloading(int got, int total) => total > 0
      ? (
          doing: 'Downloading, ${got ~/ 1000000} of ${total ~/ 1000000} MB…',
          done: (got / total).clamp(0.0, 1.0),
        )
      : (doing: 'Downloading, ${got ~/ 1000000} MB…', done: null);

  /// Downloads [url] to [to], checked against [sha256] (hex) when given,
  /// and says how much has come to [progress] (bytes, and the whole, 0 when
  /// unknown), a tenth of a megabyte at a time. One that sends nothing for
  /// [idle] is given up. Throws [InstallTrouble], leaving nothing behind.
  static Future<void> download(
    Uri url,
    File to, {
    required String name,
    String sha256 = '',
    void Function(int got, int total)? progress,
    Duration idle = const Duration(seconds: 60),
  }) async {
    final host = url.host;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    final hash = Sha256().newHashSink();
    try {
      final HttpClientResponse res;
      try {
        final req = await client.getUrl(url);
        req.headers.set('User-Agent', 'Helmy');
        res = await req.close().timeout(idle);
      } on Object {
        throw InstallTrouble(
          "$name's download at $host didn't answer. Check the internet connection (a network "
          'that blocks $host blocks it too) and try again.',
        );
      }
      if (res.statusCode != 200) {
        throw InstallTrouble("$name's download at $host failed (${res.statusCode}). Try again.");
      }
      final total = res.contentLength < 0 ? 0 : res.contentLength;
      final sink = to.openWrite();
      var got = 0, said = -1000000;
      try {
        await for (final chunk in res.timeout(idle)) {
          sink.add(chunk);
          hash.add(chunk);
          got += chunk.length;
          if (got - said >= 100000 || got == total) {
            said = got;
            progress?.call(got, total);
          }
        }
      } on TimeoutException {
        throw InstallTrouble(
          "$name's download stopped coming, after ${got ~/ 1000000} MB. Check the internet "
          'connection and try again.',
        );
      } on IOException {
        throw InstallTrouble(
          "$name's download was cut off, after ${got ~/ 1000000} MB. Try again.",
        );
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) {
        throw InstallTrouble(
          "$name's download was cut off, after ${got ~/ 1000000} MB. Try again.",
        );
      }
      hash.close();
      if (sha256.isNotEmpty) {
        final digest = [
          for (final b in (await hash.hash()).bytes) b.toRadixString(16).padLeft(2, '0'),
        ].join();
        if (digest != sha256.toLowerCase()) {
          throw InstallTrouble(
            "$name's download didn't match its maker's checksum, so it wasn't opened. Try again.",
          );
        }
      }
    } catch (_) {
      if (to.existsSync()) await to.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Runs [exe] with nothing to type into, telling each line it writes to
  /// [onLine] (a line ends at a newline or a carriage return, so a progress
  /// meter is heard as it moves) and calling [tick] each second. One that
  /// writes nothing and whose [growth] (bytes landed) does not move for
  /// [stall] is stopped. Its exit code; throws [InstallTrouble] when it
  /// would not start or was stopped.
  static Future<int> watch(
    String exe,
    List<String> args, {
    required Map<String, String> environment,
    required Duration stall,
    required String name,
    void Function(String line)? onLine,
    int Function()? growth,
    void Function()? tick,
  }) async {
    final Process p;
    try {
      p = await Process.start(exe, args, environment: environment);
    } on ProcessException {
      throw InstallTrouble("$name couldn't start on this computer.");
    }
    unawaited(p.stdin.close().catchError((_) {}));
    var heard = DateTime.now();
    var grown = growth?.call() ?? 0;
    Future<void> listen(Stream<List<int>> s) {
      var rest = '';
      final done = Completer<void>();
      s
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (text) {
              heard = DateTime.now();
              final parts = (rest + text).split(RegExp(r'\r\n|\r|\n'));
              rest = parts.removeLast();
              for (final line in parts) {
                if (line.trim().isNotEmpty) onLine?.call(line);
              }
            },
            onDone: () {
              if (rest.trim().isNotEmpty) onLine?.call(rest);
              done.complete();
            },
          );
      return done.future;
    }

    final read = Future.wait([listen(p.stdout), listen(p.stderr)]);
    var stalled = false;
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      tick?.call();
      final now = growth?.call() ?? 0;
      if (now != grown) {
        grown = now;
        heard = DateTime.now();
      }
      if (DateTime.now().difference(heard) > stall) {
        stalled = true;
        stopAll(p.pid);
        p.kill(ProcessSignal.sigkill);
      }
    });
    final code = await p.exitCode;
    // Its last lines, often what went wrong, are heard before it is done:
    // they can come after it exits. A program it left running may hold
    // them open, so not for ever.
    await read.timeout(const Duration(seconds: 5), onTimeout: () => const []);
    timer.cancel();
    if (stalled) {
      throw InstallTrouble(
        '$name sat still for ${_minutes(stall)} with nothing to show, so Helmy stopped it. '
        'Check the internet connection and try again.',
      );
    }
    return code;
  }

  /// Stops what process [pid] started (an installer's download, its
  /// unpacking) as well as it: on Windows its whole tree, elsewhere its
  /// children.
  static void stopAll(int pid) {
    try {
      if (Platform.isWindows) {
        Process.runSync('taskkill', ['/PID', '$pid', '/T', '/F']);
      } else {
        Process.runSync('pkill', ['-KILL', '-P', '$pid']);
      }
    } on Object {
      // Nothing to stop, or no way to: the installer itself still stops.
    }
  }

  static String _minutes(Duration d) =>
      d.inSeconds < 120 ? '${d.inSeconds} seconds' : '${d.inMinutes} minutes';

  /// How much an installer has downloaded: in a folder made since [since]
  /// in one of [roots] (where mktemp makes them), or in a root itself, that
  /// holds a file with one of [names], the size of its largest file
  /// changed since then; 0 while there is none.
  static int landedIn(List<Directory> roots, Set<String> names, DateTime since) {
    var most = 0;
    bool fresh(FileSystemEntity e) {
      try {
        return e.statSync().modified.isAfter(since);
      } on FileSystemException {
        return false;
      }
    }

    void measure(Directory d) {
      try {
        final files = d.listSync(followLinks: false).whereType<File>().toList();
        if (!files.any((f) => names.contains(baseName(f.path)))) return;
        for (final f in files) {
          final st = f.statSync();
          if (st.modified.isAfter(since) && st.size > most) most = st.size;
        }
      } on FileSystemException {
        // Being written to or cleaned up: nothing to count this moment.
      }
    }

    for (final root in roots) {
      measure(root);
      try {
        for (final d in root.listSync(followLinks: false).whereType<Directory>()) {
          if (fresh(d)) measure(d);
        }
      } on FileSystemException {
        // Not there, or not ours to read: nothing landed in it.
      }
    }
    return most;
  }

  /// The size of release asset [asset] in GitHub repository [repo]'s newest
  /// release; null when GitHub would not say (offline, or asked too often).
  static Future<int?> _githubAssetSize(String repo, String asset) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
      );
      req.headers.set('User-Agent', 'Helmy');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      for (final a in (json['assets'] as List? ?? const []).whereType<Map>()) {
        if (a['name'] == asset) return a['size'] as int?;
      }
      return null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _text(Uri url, String host) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(url);
      req.headers.set('User-Agent', 'Helmy');
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      return body;
    } on Object {
      throw InstallTrouble(
        "$host didn't answer. Check the internet connection (a network that blocks $host "
        'blocks it too) and try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Whether Helmy runs as an arm64 program, as Dart says where it runs
  /// ('... on "macos_arm64"'). Read from that rather than dart:ffi, which
  /// the web build (the phone's and Chrome's page) cannot compile.
  static bool get _arm => isArm(Platform.version);

  /// Whether Dart's [version] line names an arm64 processor.
  static bool isArm(String version) => RegExp(r'on "[a-z]+_arm64"').hasMatch(version);

  /// Whether this is an Apple-silicon Mac, even when Helmy runs translated:
  /// the native build is the one to install.
  static Future<bool> _armMac() async {
    if (_arm || !Platform.isMacOS) return _arm;
    try {
      final r = await Process.run('/usr/sbin/sysctl', ['-n', 'sysctl.proc_translated']);
      return '${r.stdout}'.trim() == '1';
    } on Object {
      return false;
    }
  }

  /// Whether this Linux uses musl rather than glibc (Alpine).
  static Future<bool> _musl() async {
    if (!Platform.isLinux) return false;
    if (File('/lib/libc.musl-x86_64.so.1').existsSync() ||
        File('/lib/libc.musl-aarch64.so.1').existsSync()) {
      return true;
    }
    try {
      final r = await Process.run('ldd', ['/bin/ls']);
      return '${r.stdout}${r.stderr}'.contains('musl');
    } on Object {
      return false;
    }
  }

  /// The folder a Mac's mktemp makes its folders in, whatever TMPDIR says:
  /// the person's own temporary folder, as the system names it.
  static Future<Directory?> _macUserTemp() async {
    if (!Platform.isMacOS) return null;
    try {
      final r = await Process.run('/usr/bin/getconf', ['DARWIN_USER_TEMP_DIR']);
      final dir = '${r.stdout}'.trim();
      return dir.isEmpty ? null : Directory(dir);
    } on Object {
      return null;
    }
  }

  static bool _writable(Directory d) {
    try {
      final probe = File('${d.path}/.helmy-${DateTime.now().microsecondsSinceEpoch}');
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on Object {
      return false;
    }
  }
}
