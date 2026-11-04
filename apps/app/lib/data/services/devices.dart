import 'dart:convert';
import 'dart:io';

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
    final android = await _run('adb', ['devices']);
    if (android != null && android.exitCode == 0) {
      for (final line in '${android.stdout}'.split('\n').skip(1)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length == 2 && parts[1] == 'device') {
          out.add(Device(id: parts[0], name: parts[0], ios: false, booted: true));
        }
      }
    }
    out.sort((a, b) => a.booted == b.booted ? a.name.compareTo(b.name) : (a.booted ? -1 : 1));
    return out;
  }

  /// Starts [d] (an iOS simulator) and waits until it is up.
  Future<bool> boot(Device d) async {
    if (!d.ios || d.booted) return true;
    await _run('xcrun', ['simctl', 'boot', d.id]);
    return (await _run('xcrun', ['simctl', 'bootstatus', d.id, '-b']))?.exitCode == 0;
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
  Future<bool> installIosInput() async {
    final brew = await _locator.find('brew');
    if (brew == null) return false;
    await _run('brew', ['tap', 'cameroncooke/axe']);
    final r = await _run('brew', ['install', 'cameroncooke/axe/axe']);
    _locator.forget('axe');
    return r?.exitCode == 0 && await iosInput();
  }
}
