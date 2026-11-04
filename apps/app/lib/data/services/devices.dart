import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cli_locator.dart';

/// A simulator or emulator on this computer.
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.ios,
    required this.booted,
    this.runtime = '',
  });

  /// The simulator's UDID, or the emulator's adb serial.
  final String id;
  final String name;

  /// An iOS Simulator; false for an Android emulator.
  final bool ios;
  final bool booted;
  final String runtime;
}

/// Simulators and emulators: which there are, starting one, its screen, and
/// tapping, swiping, typing and pressing home on it. iOS through Xcode's
/// `simctl` (and AXe for input, when installed); Android through `adb`.
class DeviceService {
  DeviceService(this._locator);
  final CliLocator _locator;

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
    final android = await _run('adb', ['devices']);
    if (android != null && android.exitCode == 0) {
      for (final line in '${android.stdout}'.split('\n').skip(1)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length == 2 && parts[1] == 'device') {
          final avd = parts[0].startsWith('emulator-') ? await _avdOf(parts[0]) : null;
          if (avd != null) running.add(avd);
          out.add(
            Device(
              id: parts[0],
              name: avd == null ? parts[0] : _avdName(avd),
              ios: false,
              booted: true,
              runtime: 'Android',
            ),
          );
        }
      }
    }
    for (final avd in await _avds()) {
      if (running.contains(avd)) continue;
      out.add(
        Device(id: 'avd:$avd', name: _avdName(avd), ios: false, booted: false, runtime: 'Android'),
      );
    }
    out.sort((a, b) => a.booted == b.booted ? a.name.compareTo(b.name) : (a.booted ? -1 : 1));
    return out;
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
    if (!d.ios) return null;
    final axe = await _locator.find('axe');
    if (axe == null) return null;
    final Process p;
    try {
      p = await Process.start(axe, [
        'stream-video', '--udid', d.id, '--format', 'mjpeg', //
        '--fps', '24', '--quality', '75', '--scale', '1.0',
      ], environment: await _locator.environment());
    } on ProcessException {
      return null;
    }
    unawaited(p.stderr.drain<void>());
    late final StreamController<Uint8List> out;
    final buf = BytesBuilder(copy: false);
    out = StreamController<Uint8List>(onCancel: () => p.kill());
    // Each frame is a JPEG between its start (FF D8) and end (FF D9) marks.
    var pending = Uint8List(0);
    p.stdout.listen((chunk) {
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
        out.add(pending.sublist(start, end + 2));
        pending = pending.sublist(end + 2);
      }
    }, onDone: () => out.close());
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

  /// Taps [d] at ([x], [y]) in its screen's points (iOS) or pixels (Android).
  Future<bool> tap(Device d, double x, double y) async {
    final r = d.ios
        ? await _run('axe', ['tap', '-x', '${x.round()}', '-y', '${y.round()}', '--udid', d.id])
        : await _run('adb', ['-s', d.id, 'shell', 'input', 'tap', '${x.round()}', '${y.round()}']);
    return r?.exitCode == 0;
  }

  /// Swipes on [d] from one point to another.
  Future<bool> swipe(Device d, (double, double) from, (double, double) to) async {
    final (x1, y1) = from;
    final (x2, y2) = to;
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
    final r = d.ios
        ? await _run('axe', ['type', text, '--udid', d.id])
        : await _run('adb', ['-s', d.id, 'shell', 'input', 'text', text.replaceAll(' ', '%s')]);
    return r?.exitCode == 0;
  }

  /// Presses [d]'s home button.
  Future<bool> home(Device d) async {
    final r = d.ios
        ? await _run('axe', ['button', 'home', '--udid', d.id])
        : await _run('adb', ['-s', d.id, 'shell', 'input', 'keyevent', 'KEYCODE_HOME']);
    return r?.exitCode == 0;
  }

  /// Turns [d]'s dark mode on or off (iOS).
  Future<bool> appearance(Device d, {required bool dark}) async {
    if (!d.ios) return false;
    final r = await _run('xcrun', ['simctl', 'ui', d.id, 'appearance', dark ? 'dark' : 'light']);
    return r?.exitCode == 0;
  }

  /// Whether [d] is in dark mode; null when it cannot say (Android).
  Future<bool?> isDark(Device d) async {
    if (!d.ios) return null;
    final r = await _run('xcrun', ['simctl', 'ui', d.id, 'appearance']);
    if (r == null || r.exitCode != 0) return null;
    return '${r.stdout}'.trim() == 'dark';
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
