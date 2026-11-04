import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/platform.dart';
import 'cdp.dart';
import 'chromium_tab.dart';

/// A Chromium-based browser on this computer that Preview can draw pages with.
class ChromiumBrowser {
  const ChromiumBrowser({
    required this.name,
    required this.executable,
    this.version = '',
    this.helmys = false,
  });

  final String name;

  /// The program to start; also what identifies it in settings.
  final String executable;
  final String version;

  /// Chrome for Testing that Helmy downloaded, in its own folder.
  final bool helmys;

  /// "Brave Browser 151.1.93", or just its name when the version is unknown.
  String get label => version.isEmpty ? name : '$name $version';
}

/// Where Chrome for Testing comes from, and how big it is.
typedef ChromiumDownload = ({String version, String url, int? bytes});

/// Chromium-based browsers for Preview: which are installed, Chrome for
/// Testing when none is (downloaded only once the user agrees), and one
/// running hidden, under Helmy's own profile, that pages open in.
class ChromiumService {
  ChromiumService({
    required this._appData,
    bool Function(String path)? exists,
    Map<String, String>? environment,
  }) : _exists = exists ?? ((p) => File(p).existsSync()),
       _env = environment ?? Platform.environment;

  final Future<Directory> Function() _appData;
  final bool Function(String path) _exists;
  final Map<String, String> _env;

  Future<Directory> _dir(String name) async {
    final d = Directory('${(await _appData()).path}/chromium/$name');
    await d.create(recursive: true);
    return d;
  }

  /// Every Chromium-based browser found, the one Helmy would pick first.
  Future<List<ChromiumBrowser>> installed() async {
    final found = <ChromiumBrowser>[];
    final seen = <String>{};
    Future<void> add(String name, String exe) async {
      if (!seen.add(exe) || !_exists(exe)) return;
      found.add(ChromiumBrowser(name: name, executable: exe, version: await _version(exe)));
    }

    switch (Desktop.current) {
      case .mac:
        final home = _env['HOME'] ?? '';
        for (final root in ['/Applications', '$home/Applications']) {
          for (final (app, exe) in _macApps) {
            await add(app, '$root/$app.app/Contents/MacOS/$exe');
          }
        }
      case .windows:
        final roots = [
          _env['ProgramFiles'],
          _env['ProgramFiles(x86)'],
          _env['LOCALAPPDATA'],
        ].nonNulls;
        for (final root in roots) {
          for (final (name, path) in _windowsApps) {
            await add(name, '$root\\$path');
          }
        }
      case .linux:
        for (final (name, exe) in _linuxApps) {
          for (final dir in (_env['PATH'] ?? '/usr/bin').split(':')) {
            await add(name, '$dir/$exe');
          }
        }
    }
    // Chrome for Testing that Helmy downloaded.
    final own = await _downloaded();
    if (own != null && _exists(own)) {
      found.add(
        ChromiumBrowser(
          name: 'Chrome for Testing',
          executable: own,
          version: await _version(own),
          helmys: true,
        ),
      );
    }
    return found;
  }

  // The order Helmy picks in: the browsers people use most, then the rest.
  static const _macApps = [
    ('Google Chrome', 'Google Chrome'),
    ('Brave Browser', 'Brave Browser'),
    ('Microsoft Edge', 'Microsoft Edge'),
    ('Chromium', 'Chromium'),
    ('Vivaldi', 'Vivaldi'),
    ('Google Chrome for Testing', 'Google Chrome for Testing'),
  ];
  static const _windowsApps = [
    ('Google Chrome', r'Google\Chrome\Application\chrome.exe'),
    ('Brave', r'BraveSoftware\Brave-Browser\Application\brave.exe'),
    ('Microsoft Edge', r'Microsoft\Edge\Application\msedge.exe'),
    ('Chromium', r'Chromium\Application\chrome.exe'),
    ('Vivaldi', r'Vivaldi\Application\vivaldi.exe'),
  ];
  static const _linuxApps = [
    ('Google Chrome', 'google-chrome'),
    ('Google Chrome', 'google-chrome-stable'),
    ('Brave', 'brave-browser'),
    ('Microsoft Edge', 'microsoft-edge'),
    ('Chromium', 'chromium'),
    ('Chromium', 'chromium-browser'),
    ('Vivaldi', 'vivaldi'),
  ];

  /// Its version, from a Mac app's Info.plist; empty elsewhere or unknown.
  Future<String> _version(String exe) async {
    final at = exe.indexOf('.app/Contents/MacOS/');
    if (at < 0 || !Platform.isMacOS) return '';
    try {
      final r = await Process.run('/usr/bin/plutil', [
        '-extract', 'CFBundleShortVersionString', 'raw', //
        '${exe.substring(0, at)}.app/Contents/Info.plist',
      ]);
      return r.exitCode == 0 ? '${r.stdout}'.trim() : '';
    } on ProcessException {
      return '';
    }
  }

  /// The browser to use: [preferred] when it is still installed, else the
  /// first Helmy would pick; null when there is none.
  Future<ChromiumBrowser?> pick(String? preferred) async {
    final all = await installed();
    return all.where((b) => b.executable == preferred).firstOrNull ?? all.firstOrNull;
  }

  // Chrome for Testing.

  /// This computer's name for its kind in Chrome for Testing's downloads.
  static Future<String?> _platform() async {
    if (Platform.isWindows) return 'win64';
    final arch = (await Process.run('uname', ['-m'])).stdout.toString().trim();
    if (Platform.isMacOS) return arch == 'arm64' ? 'mac-arm64' : 'mac-x64';
    if (Platform.isLinux) return arch == 'aarch64' ? 'linux-arm64' : 'linux64';
    return null;
  }

  Future<String?> _downloaded() async {
    final dir = await _dir('chrome-for-testing');
    final p = await _platform();
    return switch (p) {
      'mac-arm64' || 'mac-x64' =>
        '${dir.path}/chrome-$p/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
      'win64' => '${dir.path}\\chrome-win64\\chrome.exe',
      'linux64' || 'linux-arm64' => '${dir.path}/chrome-$p/chrome',
      _ => null,
    };
  }

  /// The current stable Chrome for Testing for this computer, with its
  /// size; null when it cannot be found out (offline).
  Future<ChromiumDownload?> latest() async {
    final client = HttpClient();
    try {
      final p = await _platform();
      final req = await client.getUrl(
        Uri.parse(
          'https://googlechromelabs.github.io/chrome-for-testing/'
          'last-known-good-versions-with-downloads.json',
        ),
      );
      final res = await req.close();
      final json = jsonDecode(await utf8.decodeStream(res)) as Map;
      return parseLatest(json, p);
    } on Object {
      return null;
    } finally {
      client.close();
    }
  }

  /// Chrome for Testing's download for [platform] in its feed.
  static ChromiumDownload? parseLatest(Map json, String? platform) {
    final stable = (json['channels'] as Map?)?['Stable'] as Map?;
    final downloads = ((stable?['downloads'] as Map?)?['chrome'] as List?) ?? const [];
    final url = downloads.whereType<Map>().where((d) => d['platform'] == platform).firstOrNull;
    if (stable == null || url == null) return null;
    return (version: '${stable['version']}', url: '${url['url']}', bytes: null);
  }

  /// How big [download] is, asked of where it comes from.
  Future<int?> sizeOf(ChromiumDownload download) async {
    final client = HttpClient();
    try {
      final res = await (await client.headUrl(Uri.parse(download.url))).close();
      await res.drain<void>();
      return res.contentLength > 0 ? res.contentLength : null;
    } on Object {
      return null;
    } finally {
      client.close();
    }
  }

  /// Downloads and unpacks [download]; [progress] hears the share done (0
  /// to 1). The browser, or null when it did not finish.
  Future<ChromiumBrowser?> fetch(
    ChromiumDownload download, {
    void Function(double share)? progress,
  }) async {
    final dir = await _dir('chrome-for-testing');
    final zip = File('${dir.path}/download.zip');
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(download.url))).close();
      if (res.statusCode != 200) return null;
      final total = res.contentLength;
      var got = 0;
      final sink = zip.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) progress?.call(got / total);
      }
      await sink.close();
      // Unpacked as the system does, keeping the app's signature whole.
      final unpack = Platform.isMacOS
          ? await Process.run('/usr/bin/ditto', ['-x', '-k', zip.path, dir.path])
          : Platform.isWindows
          ? await Process.run('tar', ['-xf', zip.path, '-C', dir.path])
          : await Process.run('unzip', ['-oq', zip.path, '-d', dir.path]);
      if (unpack.exitCode != 0) return null;
      return (await installed()).where((b) => b.helmys).firstOrNull;
    } on Object {
      return null;
    } finally {
      client.close();
      if (zip.existsSync()) await zip.delete();
    }
  }

  // The browser that pages open in.

  Process? _process;
  Cdp? _cdp;
  String? _running;
  int? _port;
  Future<Cdp>? _starting;

  /// [browser], running hidden under Helmy's own profile, started on first
  /// ask; another browser asked for replaces it.
  Future<Cdp> _browser(ChromiumBrowser browser) {
    if (_running == browser.executable && (_cdp?.isOpen ?? false)) return Future.value(_cdp!);
    // Still starting: the same start. Started and since gone: a new one.
    if (_running == browser.executable && _starting != null && _cdp == null) return _starting!;
    unawaited(stop());
    _running = browser.executable;
    return _starting = _start(browser);
  }

  /// Pixels a point on the screen pages show on; set by the app.
  double scale = 2;

  Future<Cdp> _start(ChromiumBrowser browser) async {
    // Its own profile per browser: they cannot share one, and the user's
    // own browsing, tabs and logins are never touched.
    final profile = await _dir('profiles/${browser.name.replaceAll(RegExp(r'\W+'), '-')}');
    final p = _process = await Process.start(browser.executable, [
      '--headless=new',
      // As sharp as the screen it shows on: a hidden browser draws at one
      // pixel a point otherwise, whatever the page is told.
      '--force-device-scale-factor=$scale',
      '--remote-debugging-port=0',
      '--remote-allow-origins=*',
      '--user-data-dir=${profile.path}',
      '--no-first-run',
      '--no-default-browser-check',
      'about:blank',
    ]);
    final ws = Completer<String>();
    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      final m = RegExp(r'DevTools listening on (ws://\S+)').firstMatch(l);
      if (m != null && !ws.isCompleted) ws.complete(m[1]);
    });
    unawaited(
      p.exitCode.then((_) {
        if (!ws.isCompleted) ws.completeError(CdpError('${browser.name} closed as it started.'));
      }),
    );
    final url = await ws.future.timeout(const Duration(seconds: 20));
    _port = Uri.parse(url).port;
    return _cdp = await Cdp.connect(url);
  }

  /// A new page in [browser].
  Future<ChromiumTab> open(ChromiumBrowser browser) async {
    final cdp = await _browser(browser);
    final created = await cdp.send('Target.createTarget', {'url': 'about:blank'});
    final targetId = '${created['targetId']}';
    final attached = await cdp.send('Target.attachToTarget', {
      'targetId': targetId,
      'flatten': true,
    });
    final tab = ChromiumTab(cdp, targetId: targetId, session: '${attached['sessionId']}');
    await tab.ready();
    return tab;
  }

  /// Opens Chrome's DevTools on [tab], the live page, in a window of
  /// [browser] of its own (its own profile too).
  Future<bool> inspect(ChromiumBrowser browser, ChromiumTab tab) async {
    final port = _port;
    if (port == null) return false;
    final front =
        'http://127.0.0.1:$port/devtools/inspector.html?ws=127.0.0.1:$port/devtools/page/${tab.targetId}';
    final profile = await _dir('profiles/devtools');
    try {
      await Process.start(browser.executable, [
        '--user-data-dir=${profile.path}',
        '--no-first-run',
        '--no-default-browser-check',
        '--app=$front',
      ], mode: ProcessStartMode.detached);
      return true;
    } on ProcessException {
      return false;
    }
  }

  /// Ends the browser, if one is running.
  Future<void> stop() async {
    final cdp = _cdp;
    _cdp = null;
    _starting = null;
    _running = null;
    try {
      await cdp?.send('Browser.close').timeout(const Duration(seconds: 2));
    } on Object {
      // Already gone.
    }
    _process?.kill();
    _process = null;
  }
}
