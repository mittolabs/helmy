import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/iphones.dart';
import 'cli_locator.dart';
import 'sim_input.dart';

/// A simulator or emulator on this computer, or a real phone it reaches.
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.ios,
    required this.booted,
    this.runtime = '',
    this.physical = false,
  });

  /// The simulator's UDID, the emulator's or phone's adb serial, or the
  /// iPhone's CoreDevice id.
  final String id;
  final String name;

  /// iOS (a simulator or an iPhone); false for Android.
  final bool ios;
  final bool booted;
  final String runtime;

  /// A real phone, not a simulator or emulator.
  final bool physical;

  /// A real iPhone or iPad: Apple lets apps be installed and launched on it,
  /// and their output read, but its screen is not shown or tapped from here.
  bool get realIphone => ios && physical;

  Device get started =>
      Device(id: id, name: name, ios: ios, booted: true, runtime: runtime, physical: physical);
}

/// Simulators and emulators: which there are, starting one, its screen, and
/// tapping, swiping, typing and pressing home on it. iOS through Xcode's
/// `simctl` (and AXe for input, when installed: through Helmy's own
/// resident helper, [SimInput], which costs milliseconds, else the `axe`
/// command); Android through `adb`.
class DeviceService {
  DeviceService(this._locator, {this._input});
  final CliLocator _locator;
  final SimInput? _input;

  Future<ProcessResult?> _run(String cmd, List<String> args, {bool binary = false}) async {
    final bin = cmd == 'xcrun' ? '/usr/bin/xcrun' : await _locator.find(cmd);
    if (bin == null || !(cmd != 'xcrun' || Platform.isMacOS)) return null;
    try {
      return await Process.run(
        bin,
        args,
        stdoutEncoding: binary ? null : systemEncoding,
        environment: await _locator.environment(),
      ).timeout(const Duration(seconds: 60));
    } on Object {
      return null;
    }
  }

  /// Whether taps and typing reach iOS simulators here (AXe is installed).
  Future<bool> iosInput() async => await _locator.find('axe') != null;

  /// Every iPhone simulator and Android emulator there is, booted first.
  Future<List<Device>> list() async {
    final out = <Device>[];
    final ios = await _run('xcrun', ['simctl', 'list', 'devices', 'available', '--json']);
    if (ios != null && ios.exitCode == 0) {
      final byRuntime = (jsonDecode('${ios.stdout}') as Map)['devices'] as Map;
      for (final e in byRuntime.entries) {
        // "com.apple.CoreSimulator.SimRuntime.iOS-26-5" reads "iOS 26.5".
        final runtime = '${e.key}'.split('.').last.replaceFirst('-', ' ').replaceAll('-', '.');
        for (final d in (e.value as List).whereType<Map>()) {
          final name = '${d['name']}';
          if (!name.startsWith('iPhone') && !name.startsWith('iPad')) continue;
          out.add(
            Device(
              id: '${d['udid']}',
              name: name,
              ios: true,
              booted: d['state'] == 'Booted',
              runtime: runtime,
            ),
          );
        }
      }
    }
    // Android: the emulators running (adb), named by their virtual device,
    // then the virtual devices not running, to start.
    final running = <String>{};
    final android = await _run('adb', ['devices', '-l']);
    if (android != null && android.exitCode == 0) {
      for (final line in '${android.stdout}'.split('\n').skip(1)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2 || parts[1] != 'device') continue;
        final serial = parts[0];
        final emulator = serial.startsWith('emulator-');
        final avd = emulator ? await _avdOf(serial) : null;
        if (avd != null) running.add(avd);
        // A phone on the cable: its model, as adb says it ("Pixel_5").
        final model = parts
            .where((p) => p.startsWith('model:'))
            .map((p) => p.substring(6).replaceAll('_', ' '))
            .firstOrNull;
        out.add(
          Device(
            id: serial,
            name: avd != null ? _avdName(avd) : (model ?? serial),
            ios: false,
            booted: true,
            runtime: emulator ? 'Android emulator' : 'Android phone',
            physical: !emulator,
          ),
        );
      }
    }
    for (final avd in await _avds()) {
      if (running.contains(avd)) continue;
      out.add(
        Device(
          id: 'avd:$avd',
          name: _avdName(avd),
          ios: false,
          booted: false,
          runtime: 'Android emulator',
        ),
      );
    }
    for (final phone in await iphones()) {
      out.add(
        Device(
          id: phone.id,
          name: phone.name,
          ios: true,
          booted: true,
          runtime: 'iOS ${phone.os}${phone.wired ? '' : ', over Wi-Fi'}',
          physical: true,
        ),
      );
    }
    // A real phone first, then what is running, then the rest.
    int rank(Device d) => d.physical ? 0 : (d.booted ? 1 : 2);
    out.sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.name.compareTo(b.name));
    return out;
  }

  // Real iPhones, through Xcode's devicectl: listed, their apps installed
  // and launched, and what a launched app prints kept as its logs.

  /// devicectl writes its JSON only to a file: run with [args], read back.
  Future<(bool, String)> _devicectl(List<String> args) async {
    final file = File(
      '${Directory.systemTemp.path}/helmy-devicectl-$pid-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    final r = await _run('xcrun', ['devicectl', ...args, '--json-output', file.path]);
    var json = '';
    try {
      json = await file.readAsString();
      await file.delete();
    } on FileSystemException {
      // It wrote nothing: what it printed says why.
    }
    if (r == null) return (false, json);
    final ok = r.exitCode == 0;
    return (ok, ok ? json : (json.isNotEmpty ? json : '${r.stderr}\n${r.stdout}'));
  }

  /// The iPhones and iPads paired with this Mac that Apple reaches now.
  Future<List<Iphone>> iphones() async {
    if (!Platform.isMacOS) return const [];
    final (ok, json) = await _devicectl(['list', 'devices', '--timeout', '5']);
    return ok ? iphonesFrom(json) : const [];
  }

  /// The apps on real iPhone [d] that their developer built; a list, or why
  /// they cannot be read (with what fixes it).
  Future<(List<PhoneApp>?, String?)> phoneApps(Device d) async {
    final (ok, out) = await _devicectl([
      'device', 'info', 'apps', '--device', d.id, '--timeout', '30', //
    ]);
    return ok ? (phoneAppsFrom(out), null) : (null, phoneTrouble(d.name, out));
  }

  /// Installs the app at [path] (a built .app, or an .ipa or .apk) on [d]:
  /// null when done, else why not and what fixes it.
  Future<String?> install(Device d, String path) async {
    if (!File(path).existsSync() && !Directory(path).existsSync()) {
      return 'There is nothing at $path to install.';
    }
    if (d.realIphone) {
      final (ok, out) = await _devicectl([
        'device', 'install', 'app', '--device', d.id, '--timeout', '120', path, //
      ]);
      return ok ? null : phoneTrouble(d.name, out);
    }
    final r = d.ios
        ? await _run('xcrun', ['simctl', 'install', d.id, path])
        : await _run('adb', ['-s', d.id, 'install', '-r', path]);
    if (r != null && r.exitCode == 0) return null;
    final said = '${r?.stderr ?? ''}'.trim().split('\n').lastOrNull ?? '';
    return "${d.name} didn't install it${said.isEmpty ? '.' : ': $said'}";
  }

  /// What the apps launched on each real iPhone printed, newest last, kept
  /// while they run: an iPhone's own log is not readable from here.
  final _console = <String, List<String>>{};
  final _consoleRuns = <String, Process>{};
  static const _consoleMax = 2000;

  /// Opens [app] (a bundle id, or an Android package) on [d], closing it
  /// first if it is open: null when it opened, else why not and what fixes
  /// it. On a real iPhone, what it prints is kept as its logs.
  Future<String?> launch(Device d, String app) async {
    if (d.realIphone) return _launchOnIphone(d, app);
    final r = d.ios
        ? await _run('xcrun', ['simctl', 'launch', '--terminate-running-process', d.id, app])
        : await _run('adb', [
            '-s', d.id, 'shell', 'monkey', '-p', app, //
            '-c', 'android.intent.category.LAUNCHER', '1',
          ]);
    if (r != null && r.exitCode == 0 && !'${r.stdout}'.contains('No activities found')) {
      return null;
    }
    return "${d.name} didn't open $app. Is it installed?";
  }

  Future<String?> _launchOnIphone(Device d, String app) async {
    _consoleRuns.remove(d.id)?.kill();
    final Process p;
    try {
      p = await Process.start('/usr/bin/xcrun', [
        'devicectl', 'device', 'process', 'launch', '--console', '--terminate-existing', //
        '--device', d.id, '--timeout', '60', app,
      ], environment: await _locator.environment());
    } on ProcessException {
      return "Xcode's device tools aren't here. Install Xcode to use ${d.name}.";
    }
    _consoleRuns[d.id] = p;
    final lines = _console[d.id] = [];
    final said = StringBuffer();
    final opened = Completer<String?>();
    void take(String line) {
      said.writeln(line);
      // devicectl says when the app is up; after that, each line is the app's.
      if (!opened.isCompleted && line.contains('Launched application')) {
        opened.complete(null);
        return;
      }
      if (opened.isCompleted) {
        lines.add(line);
        if (lines.length > _consoleMax) lines.removeRange(0, lines.length - _consoleMax);
      }
    }

    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(take);
    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(take);
    unawaited(
      p.exitCode.then((code) {
        if (_consoleRuns[d.id] == p) _consoleRuns.remove(d.id);
        if (!opened.isCompleted) {
          opened.complete(code == 0 ? null : phoneTrouble(d.name, said.toString()));
        } else {
          lines.add('($app closed)');
        }
      }),
    );
    return opened.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        p.kill();
        return "${d.name} can't be reached. Wake it, and have it on this Mac's Wi-Fi or on "
            'the cable, then try again.';
      },
    );
  }

  /// Starts [d] (an iOS simulator) and waits until it is up.
  Future<bool> boot(Device d) async {
    if (!d.ios && d.id.startsWith('avd:')) return _bootAvd(d.id.substring(4));
    if (!d.ios || d.booted) return true;
    await _run('xcrun', ['simctl', 'boot', d.id]);
    return (await _run('xcrun', ['simctl', 'bootstatus', d.id, '-b']))?.exitCode == 0;
  }

  /// The Android emulator program: where Android Studio, Homebrew or the
  /// environment put it; null when it is not installed.
  Future<String?> _emulator() async {
    final env = await _locator.environment();
    final home = env['HOME'] ?? Platform.environment['HOME'] ?? '';
    final roots = [
      env['ANDROID_HOME'],
      env['ANDROID_SDK_ROOT'],
      '$home/Library/Android/sdk',
      '$home/Android/Sdk',
      '/opt/homebrew/share/android-commandlinetools',
      '/usr/local/share/android-commandlinetools',
    ].nonNulls;
    for (final r in roots) {
      final exe = '$r/emulator/emulator${Platform.isWindows ? '.exe' : ''}';
      if (File(exe).existsSync()) return exe;
    }
    return _locator.find('emulator');
  }

  /// The Android virtual devices made on this computer.
  Future<List<String>> _avds() async {
    final exe = await _emulator();
    if (exe == null) return const [];
    try {
      final r = await Process.run(exe, ['-list-avds'], environment: await _locator.environment());
      if (r.exitCode != 0) return const [];
      return [
        for (final l in '${r.stdout}'.split('\n'))
          if (l.trim().isNotEmpty && !l.startsWith('INFO') && !l.contains(' ')) l.trim(),
      ];
    } on ProcessException {
      return const [];
    }
  }

  /// The virtual device a running emulator is.
  Future<String?> _avdOf(String serial) async {
    final r = await _run('adb', ['-s', serial, 'emu', 'avd', 'name']);
    if (r == null || r.exitCode != 0) return null;
    final name = '${r.stdout}'.split('\n').first.trim();
    return name.isEmpty ? null : name;
  }

  /// "sat_docs_demo" reads "sat docs demo".
  static String _avdName(String avd) => avd.replaceAll('_', ' ');

  /// Starts the virtual device [avd] (its window kept out of sight: it shows
  /// in the panel) and waits until Android has started.
  Future<bool> _bootAvd(String avd) async {
    final exe = await _emulator();
    if (exe == null) return false;
    try {
      await Process.start(
        exe,
        ['-avd', avd, '-no-window', '-no-boot-anim', '-no-snapshot-save'],
        environment: await _locator.environment(),
        mode: ProcessStartMode.detached,
      );
    } on ProcessException {
      return false;
    }
    final until = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final adb = await _run('adb', ['devices']);
      for (final line in '${adb?.stdout ?? ''}'.split('\n')) {
        final serial = line.trim().split(RegExp(r'\s+')).first;
        if (!serial.startsWith('emulator-') || !line.contains('device')) continue;
        if (await _avdOf(serial) != avd) continue;
        final up = await _run('adb', ['-s', serial, 'shell', 'getprop', 'sys.boot_completed']);
        if ('${up?.stdout}'.trim() == '1') return true;
      }
    }
    return false;
  }

  /// [d]'s screen now, as JPEG (iOS) or PNG (Android) bytes; null when it
  /// cannot be read.
  Future<List<int>?> screen(Device d) async {
    if (d.ios) {
      // simctl writes screenshots only to a file.
      final file = '${Directory.systemTemp.path}/helmy-device-${d.id}.jpg';
      final r = await _run('xcrun', ['simctl', 'io', d.id, 'screenshot', '--type=jpeg', file]);
      if (r == null || r.exitCode != 0 || !File(file).existsSync()) return null;
      return File(file).readAsBytes();
    }
    final r = await _run('adb', ['-s', d.id, 'exec-out', 'screencap', '-p'], binary: true);
    if (r == null || r.exitCode != 0) return null;
    final bytes = r.stdout as List<int>;
    return bytes.isEmpty ? null : bytes;
  }

  /// [d]'s screen as it changes (iOS, with AXe): JPEG frames at about 20 a
  /// second, from one process, rather than a picture asked for each time.
  /// Null when it cannot stream; cancelling the subscription ends it.
  Future<Stream<Uint8List>?> stream(Device d) async {
    final env = await _locator.environment();
    // A process whose output is JPEG frames, one after another; started
    // again when it ends while the stream is still wanted.
    Future<Process?> Function() start;
    if (d.ios) {
      final axe = await _locator.find('axe');
      if (axe == null) return null;
      start = () => Process.start(axe, [
        'stream-video', '--udid', d.id, '--format', 'mjpeg', //
        '--fps', '24', '--quality', '75', '--scale', '1.0',
      ], environment: env);
    } else {
      // Android records its own screen as video, a frame each time it
      // changes; ffmpeg turns that into pictures. At the screen's own size,
      // so taps land where they are pointed. Android ends a recording after
      // three minutes: it starts again.
      final adb = await _locator.find('adb');
      final ffmpeg = await _locator.find('ffmpeg');
      if (adb == null || ffmpeg == null || d.id.startsWith('avd:')) return null;
      start = () => Process.start('/bin/sh', [
        '-c',
        r'"$1" -s "$2" exec-out screenrecord --output-format=h264 --bit-rate 8000000 - '
            r'| "$3" -loglevel error -flags low_delay -f h264 -i - -f mjpeg -q:v 4 -',
        'sh',
        adb,
        d.id,
        ffmpeg,
      ], environment: env);
    }
    Process? p;
    var wanted = true;
    late final StreamController<Uint8List> out;
    out = StreamController<Uint8List>(
      onCancel: () {
        wanted = false;
        p?.kill();
        if (!d.ios) unawaited(_run('adb', ['-s', d.id, 'shell', 'pkill', 'screenrecord']));
      },
    );
    Future<void> run() async {
      try {
        p = await start();
      } on ProcessException {
        await out.close();
        return;
      }
      final proc = p!;
      unawaited(proc.stderr.drain<void>());
      final buf = BytesBuilder(copy: false);
      // Each frame is a JPEG between its start (FF D8) and end (FF D9) marks.
      var pending = Uint8List(0);
      await proc.stdout.forEach((chunk) {
        buf
          ..add(pending)
          ..add(chunk);
        pending = buf.takeBytes();
        while (true) {
          final start = _find(pending, 0xD8, 0);
          if (start < 0) break;
          final end = _find(pending, 0xD9, start + 2);
          if (end < 0) {
            pending = pending.sublist(start);
            break;
          }
          if (!out.isClosed) out.add(pending.sublist(start, end + 2));
          pending = pending.sublist(end + 2);
        }
      });
      if (wanted && !out.isClosed) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (wanted) unawaited(run());
      }
    }

    unawaited(run());
    return out.stream;
  }

  /// Where FF [mark] is in [b] from [from]; -1 when not there.
  static int _find(Uint8List b, int mark, int from) {
    for (var i = from; i < b.length - 1; i++) {
      if (b[i] == 0xFF && b[i + 1] == mark) return i;
    }
    return -1;
  }

  /// Presses Return or Backspace on [d]'s keyboard.
  Future<bool> keyPress(Device d, String key) async {
    // USB HID usage codes: Return 40, Backspace 42.
    final code = switch (key) {
      'Enter' => '40',
      'Backspace' => '42',
      _ => null,
    };
    if (code == null) return false;
    if (d.ios) {
      final fast = await _input?.key(d.id, int.parse(code));
      if (fast != null) return fast;
    }
    final r = d.ios
        ? await _run('axe', ['key', code, '--udid', d.id])
        : await _run('adb', [
            '-s',
            d.id,
            'shell',
            'input',
            'keyevent',
            key == 'Enter' ? '66' : '67',
          ]);
    return r?.exitCode == 0;
  }

  /// The simulators whose apps have been made readable.
  final _readableSims = <String>{};

  /// A simulator's apps show their accessibility only when it is on, which a
  /// new simulator has off: only the home screen reads until then (measured,
  /// iOS 26: Settings gave nothing, then 43 labelled elements, without
  /// relaunching). Turned on once per simulator.
  Future<void> _readable(Device d) async {
    if (!_readableSims.add(d.id)) return;
    for (final key in ['AccessibilityEnabled', 'ApplicationAccessibilityEnabled']) {
      await _run('xcrun', [
        'simctl',
        'spawn',
        d.id,
        'defaults',
        'write',
        'com.apple.Accessibility',
        key,
        '-bool',
        'true',
      ]);
    }
  }

  /// What is on [d]'s screen, as its accessibility says (AXe's JSON on iOS,
  /// uiautomator's XML on Android); null when it cannot be read.
  Future<String?> describe(Device d) async {
    if (d.ios) await _readable(d);
    final r = d.ios
        ? await _run('axe', ['describe-ui', '--udid', d.id])
        : await _run('adb', ['-s', d.id, 'exec-out', 'uiautomator', 'dump', '/dev/tty']);
    if (r == null || r.exitCode != 0) return null;
    final out = '${r.stdout}';
    return out.trim().isEmpty ? null : out;
  }

  /// [d]'s recent log lines, newest last: the last [minutes], of [app] (a
  /// process or package name) when given, else of installed apps on iOS (not
  /// the system's thousands) and warnings and errors on Android; with [find],
  /// only lines holding it; at most [max]. Null when it cannot be read.
  Future<List<String>?> logs(
    Device d, {
    String? app,
    String? find,
    int minutes = 2,
    int max = 150,
  }) async {
    final want = find?.toLowerCase();
    if (d.realIphone) {
      final printed = [
        for (final l in _console[d.id] ?? const <String>[])
          if (want == null || want.isEmpty || l.toLowerCase().contains(want)) l,
      ];
      return printed.length <= max ? printed : printed.sublist(printed.length - max);
    }
    final ProcessResult? r;
    if (d.ios) {
      final name = (app ?? '').replaceAll('"', '');
      final who = name.isEmpty
          ? 'processImagePath CONTAINS "/Containers/Bundle/Application/"'
          : 'process == "$name" OR subsystem CONTAINS "$name"';
      r = await _run('xcrun', [
        'simctl', 'spawn', d.id, 'log', 'show', '--last', '${minutes}m', //
        '--style', 'compact', '--predicate', who,
      ]);
    } else {
      String? pid;
      if (app != null && app.isNotEmpty) {
        final out = await _run('adb', ['-s', d.id, 'shell', 'pidof', app]);
        pid = '${out?.stdout ?? ''}'.trim().split(' ').first;
        if (pid.isEmpty) return ['$app is not running on ${d.name}.'];
      }
      final since = DateTime.now().subtract(Duration(minutes: minutes)).toString().substring(5, 23);
      r = await _run('adb', [
        '-s', d.id, 'logcat', '-d', '-v', 'time', '-T', since, //
        if (pid != null) '--pid=$pid' else '*:W',
      ]);
    }
    if (r == null || r.exitCode != 0) return null;
    final lines = [
      for (final l in '${r.stdout}'.split('\n'))
        if (l.trim().isNotEmpty &&
            !l.startsWith('Timestamp') &&
            !l.startsWith('---------') &&
            (want == null || want.isEmpty || l.toLowerCase().contains(want)))
          l,
    ];
    return lines.length <= max ? lines : lines.sublist(lines.length - max);
  }

  /// Taps [d] at ([x], [y]) in its screen's points (iOS) or pixels (Android).
  Future<bool> tap(Device d, double x, double y) async {
    if (d.ios) {
      final fast = await _input?.tap(d.id, x, y);
      if (fast != null) return fast;
    }
    final r = d.ios
        ? await _run('axe', ['tap', '-x', '${x.round()}', '-y', '${y.round()}', '--udid', d.id])
        : await _run('adb', ['-s', d.id, 'shell', 'input', 'tap', '${x.round()}', '${y.round()}']);
    return r?.exitCode == 0;
  }

  /// Swipes on [d] from one point to another.
  Future<bool> swipe(Device d, (double, double) from, (double, double) to) async {
    final (x1, y1) = from;
    final (x2, y2) = to;
    if (d.ios) {
      final fast = await _input?.swipe(d.id, from, to);
      if (fast != null) return fast;
    }
    final r = d.ios
        ? await _run('axe', [
            'swipe', '--start-x', '${x1.round()}', '--start-y', '${y1.round()}', //
            '--end-x', '${x2.round()}', '--end-y', '${y2.round()}', '--udid', d.id,
          ])
        : await _run('adb', [
            '-s', d.id, 'shell', 'input', 'swipe', //
            '${x1.round()}', '${y1.round()}', '${x2.round()}', '${y2.round()}',
          ]);
    return r?.exitCode == 0;
  }

  /// Types [text] into whatever has focus on [d].
  Future<bool> type(Device d, String text) async {
    // A character the helper has no key for (an accent, an emoji) goes the
    // slower way, which types anything.
    if (d.ios && await _input?.text(d.id, text) == true) return true;
    final r = d.ios
        ? await _run('axe', ['type', text, '--udid', d.id])
        : await _run('adb', ['-s', d.id, 'shell', 'input', 'text', text.replaceAll(' ', '%s')]);
    return r?.exitCode == 0;
  }

  /// Presses [d]'s home button.
  Future<bool> home(Device d) async {
    if (d.ios) {
      final fast = await _input?.home(d.id);
      if (fast != null) return fast;
    }
    final r = d.ios
        ? await _run('axe', ['button', 'home', '--udid', d.id])
        : await _run('adb', ['-s', d.id, 'shell', 'input', 'keyevent', 'KEYCODE_HOME']);
    return r?.exitCode == 0;
  }

  /// Turns [d]'s dark mode on or off (iOS).
  Future<bool> appearance(Device d, {required bool dark}) async {
    final r = d.ios
        ? await _run('xcrun', ['simctl', 'ui', d.id, 'appearance', dark ? 'dark' : 'light'])
        : await _run('adb', ['-s', d.id, 'shell', 'cmd', 'uimode', 'night', dark ? 'yes' : 'no']);
    return r?.exitCode == 0;
  }

  /// Whether [d] is in dark mode; null when it cannot say.
  Future<bool?> isDark(Device d) async {
    final r = d.ios
        ? await _run('xcrun', ['simctl', 'ui', d.id, 'appearance'])
        : await _run('adb', ['-s', d.id, 'shell', 'cmd', 'uimode', 'night']);
    if (r == null || r.exitCode != 0) return null;
    final out = '${r.stdout}'.trim();
    return d.ios ? out == 'dark' : out.endsWith('yes');
  }

  // Settings of the device itself, as T3 Code's device tools have them: what
  // a person checks an app against. Each says false where the device cannot.

  /// Whether [d] is an Android emulator, which takes a location; a phone
  /// keeps its own.
  static bool emulatorOf(Device d) => !d.ios && d.id.startsWith('emulator-');

  /// [d]'s text size, one of [DeviceText] (as each platform names its own).
  Future<bool> textSize(Device d, DeviceText size) async {
    final r = d.ios
        ? await _run('xcrun', ['simctl', 'ui', d.id, 'content_size', size.ios])
        : await _run('adb', [
            '-s',
            d.id,
            'shell',
            'settings',
            'put',
            'system',
            'font_scale',
            '${size.android}',
          ]);
    return r?.exitCode == 0;
  }

  /// [d]'s text size now; null when it cannot say.
  Future<DeviceText?> textSizeOf(Device d) async {
    final r = d.ios
        ? await _run('xcrun', ['simctl', 'ui', d.id, 'content_size'])
        : await _run('adb', ['-s', d.id, 'shell', 'settings', 'get', 'system', 'font_scale']);
    if (r == null || r.exitCode != 0) return null;
    final out = '${r.stdout}'.trim();
    if (d.ios) return DeviceText.values.where((t) => t.ios == out).firstOrNull;
    final scale = double.tryParse(out) ?? 1.0;
    return DeviceText.values.reduce(
      (a, b) => (b.android - scale).abs() < (a.android - scale).abs() ? b : a,
    );
  }

  /// Puts [d] at a place ([lat], [lon]); with none, gives it back its own.
  Future<bool> location(Device d, {double? lat, double? lon}) async {
    final ProcessResult? r;
    if (d.ios) {
      r = lat == null || lon == null
          ? await _run('xcrun', ['simctl', 'location', d.id, 'clear'])
          : await _run('xcrun', ['simctl', 'location', d.id, 'set', '$lat,$lon']);
    } else {
      if (!emulatorOf(d) || lat == null || lon == null) return false;
      r = await _run('adb', ['-s', d.id, 'emu', 'geo', 'fix', '$lon', '$lat']);
    }
    return r?.exitCode == 0;
  }

  /// Opens [url] on [d], in whatever app it is for.
  Future<bool> openUrl(Device d, String url) async {
    final r = d.ios
        ? await _run('xcrun', ['simctl', 'openurl', d.id, url])
        : await _run('adb', [
            '-s',
            d.id,
            'shell',
            'am',
            'start',
            '-a',
            'android.intent.action.VIEW',
            '-d',
            url,
          ]);
    return r?.exitCode == 0;
  }

  /// A status bar fit for screenshots (9:41, full battery), or [d]'s own.
  /// iOS simulators only.
  Future<bool> cleanStatusBar(Device d, bool clean) async {
    if (!d.ios) return false;
    final r = clean
        ? await _run('xcrun', [
            'simctl', 'status_bar', d.id, 'override', '--time', '9:41', //
            '--batteryState',
            'charged',
            '--batteryLevel',
            '100',
            '--cellularBars',
            '4',
            '--wifiBars',
            '3',
          ])
        : await _run('xcrun', ['simctl', 'status_bar', d.id, 'clear']);
    return r?.exitCode == 0;
  }

  /// Every app on [d] asks for its permissions afresh. iOS simulators only.
  Future<bool> resetPermissions(Device d) async {
    if (!d.ios) return false;
    return (await _run('xcrun', ['simctl', 'privacy', d.id, 'reset', 'all']))?.exitCode == 0;
  }

  /// Sends a push notification to the app [bundle] on [d], as [payload] (an
  /// APNs JSON body). iOS simulators only.
  Future<bool> push(Device d, String bundle, String payload) async {
    if (!d.ios) return false;
    try {
      jsonDecode(payload);
    } on FormatException {
      return false;
    }
    final dir = await Directory.systemTemp.createTemp('helmy-push');
    try {
      final file = File('${dir.path}/push.apns')..writeAsStringSync(payload);
      return (await _run('xcrun', ['simctl', 'push', d.id, bundle, file.path]))?.exitCode == 0;
    } finally {
      unawaited(dir.delete(recursive: true));
    }
  }

  /// Installs AXe, which carries taps and typing to iOS simulators, from its
  /// maker's Homebrew tap. True when it is installed after.
  ///
  /// [progress] hears what is happening as Homebrew says it: its step, and
  /// while downloading, the share done (0 to 1) it prints.
  Future<bool> installIosInput({void Function(String step, double? share)? progress}) async {
    final brew = await _locator.find('brew');
    if (brew == null) return false;
    progress?.call('Adding where AXe comes from', null);
    await _run('brew', ['tap', 'cameroncooke/axe']);
    progress?.call('Downloading AXe', null);
    final ok = await _streamed(brew, ['install', 'cameroncooke/axe/axe'], (line) {
      final pct = RegExp(r'(\d{1,3}(?:\.\d)?)%').allMatches(line).lastOrNull;
      if (pct != null) {
        progress?.call('Downloading AXe', (double.parse(pct[1]!) / 100).clamp(0.0, 1.0));
      } else if (line.contains('Pouring') || line.contains('Installing')) {
        progress?.call('Installing AXe', null);
      }
    });
    _locator.forget('axe');
    return ok && await iosInput();
  }

  /// Runs [bin] as in a terminal (so it prints its progress), each line of
  /// what it prints to [line]; true when it ends well.
  Future<bool> _streamed(String bin, List<String> args, void Function(String) line) async {
    try {
      final p = Platform.isMacOS
          ? await Process.start('/usr/bin/script', [
              '-q',
              '/dev/null',
              bin,
              ...args,
            ], environment: await _locator.environment())
          : await Process.start(bin, args, environment: await _locator.environment());
      // Progress bars redraw with a carriage return: each redraw is a line.
      void read(Stream<List<int>> s) => s
          .transform(const SystemEncoding().decoder)
          .expand((chunk) => chunk.split(RegExp(r'[\r\n]')))
          .where((l) => l.trim().isNotEmpty)
          .listen(line);
      read(p.stdout);
      read(p.stderr);
      return await p.exitCode.timeout(const Duration(minutes: 10)) == 0;
    } on Object {
      return false;
    }
  }
}

/// A device's text size, on one scale across both platforms.
enum DeviceText {
  small('Smaller', 'small', .85),
  normal('Default', 'large', 1.0),
  large('Larger', 'extra-large', 1.15),
  larger('Largest', 'extra-extra-extra-large', 1.3),
  accessibility('Accessibility size', 'accessibility-extra-large', 2.0);

  const DeviceText(this.label, this.ios, this.android);
  final String label;

  /// iOS's content size category.
  final String ios;

  /// Android's font scale.
  final double android;
}
