import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Runs a program and gives what it printed; injectable for tests.
typedef Run = Future<ProcessResult> Function(String program, List<String> args);

/// Asks Helmy's own Mac side (Swift) to do something; injectable for tests.
typedef Native = Future<Object?> Function(Map<String, Object?> args);

/// Starts a program that keeps running; injectable for tests.
typedef Start = Future<Process> Function(String program, List<String> args);

/// Something on this Mac that did not go: what happened, in plain words,
/// and the fix link that sorts it, when there is one.
class MacTrouble implements Exception {
  const MacTrouble(this.what, {this.fix});
  final String what;

  /// A `helmy://fix/...` link.
  final String? fix;

  @override
  String toString() => what;
}

/// What Helmy does on this Mac itself: keeping it awake, locking it, its
/// sound, what is using it, its battery, disk and network, quitting apps,
/// ejecting drives. Done by Helmy's own process, so no agent's sandbox is
/// in the way; the only permission any of it needs is Accessibility, for
/// what presses keys (locking, the media keys).
class MacActions {
  MacActions({Run? run, Native? native, Start? start, DateTime Function()? now})
    : _run = run ?? Process.run,
      _start = start ?? Process.start,
      _native = native ?? _channel,
      _now = now ?? DateTime.now;

  final Run _run;
  final Start _start;
  final Native _native;
  final DateTime Function() _now;

  static const _ch = MethodChannel('helmy/notify');
  static Future<Object?> _channel(Map<String, Object?> args) => _ch.invokeMethod('mac', args);

  static const accessibilityFix = 'helmy://fix/allow-accessibility';

  Future<String> _out(String program, List<String> args) async {
    final r = await _run(program, args);
    if (r.exitCode != 0) {
      final err = '${r.stderr}'.trim();
      throw MacTrouble(err.isEmpty ? '${program.split('/').last} did not finish.' : err);
    }
    return '${r.stdout}'.trim();
  }

  Future<Object?> _ask(String what, [Map<String, Object?> more = const {}]) async {
    final r = await _native({'do': what, ...more});
    if (r == 'accessibility') {
      throw const MacTrouble(
        'Helmy needs the Accessibility permission to press keys on this Mac.',
        fix: accessibilityFix,
      );
    }
    return r;
  }

  // Keeping awake.

  Process? _awake;
  DateTime? _awakeUntil;
  bool _awakeForever = false;

  /// Keeps this Mac from sleeping for [time], or until [until], or until
  /// told to stop when neither is given. The display stays on unless
  /// [display] is false.
  Future<String> keepAwake({Duration? time, DateTime? until, bool display = true}) async {
    await stopAwake();
    final end = until ?? (time == null ? null : _now().add(time));
    if (end != null && !end.isAfter(_now())) {
      throw const MacTrouble('That time has already passed.');
    }
    final seconds = end?.difference(_now()).inSeconds;
    final p = _awake = await _start('/usr/bin/caffeinate', [
      display ? '-di' : '-i',
      if (seconds != null) ...['-t', '$seconds'],
    ]);
    _awakeUntil = end;
    _awakeForever = end == null;
    unawaited(
      p.exitCode.then((_) {
        if (identical(_awake, p)) {
          _awake = null;
          _awakeUntil = null;
          _awakeForever = false;
        }
      }),
    );
    return awakeNow();
  }

  /// Lets this Mac sleep again.
  Future<String> stopAwake() async {
    final p = _awake;
    _awake = null;
    _awakeUntil = null;
    _awakeForever = false;
    p?.kill();
    return 'This Mac can sleep as usual.';
  }

  /// Whether Helmy is keeping this Mac awake, and until when.
  String awakeNow() {
    if (_awake == null) return 'Helmy is not keeping this Mac awake.';
    if (_awakeForever) return 'Helmy is keeping this Mac awake until told to stop.';
    final u = _awakeUntil!;
    final left = u.difference(_now());
    return 'Helmy is keeping this Mac awake until ${_clock(u)} (${_span(left)} from now).';
  }

  // The screen and sleep.

  /// Locks the screen now: Control-Command-Q, pressed by Helmy.
  Future<String> lock() async {
    await _ask('lock');
    return 'Locked the screen.';
  }

  Future<String> displayOff() async {
    await _out('/usr/bin/pmset', ['displaysleepnow']);
    return 'Turned the display off.';
  }

  Future<String> sleep() async {
    // A moment first, so the answer gets out before the Mac goes.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () => _run('/usr/bin/pmset', ['sleepnow'])),
    );
    return 'This Mac goes to sleep in two seconds.';
  }

  // Sound.

  Future<Map<String, String>> _volume() async {
    final s = await _out('/usr/bin/osascript', ['-e', 'get volume settings']);
    return {
      for (final part in s.split(','))
        if (part.contains(':')) part.split(':')[0].trim(): part.split(':')[1].trim(),
    };
  }

  int? _micWas;

  /// The volume, whether it is muted, the microphone and where sound goes.
  Future<String> sound() async {
    final v = await _volume();
    final outputs = await this.outputs();
    final current = outputs.where((o) => o.current).firstOrNull;
    final micMuted = v['input volume'] == '0';
    return [
      v['output muted'] == 'true'
          ? 'Sound is muted (volume ${v['output volume']} when unmuted).'
          : 'Volume is ${v['output volume']} of 100.',
      micMuted ? 'The microphone is muted.' : 'The microphone is on (level ${v['input volume']}).',
      if (current != null) 'Sound plays through ${current.name}.',
      if (outputs.length > 1)
        'Other outputs: ${outputs.where((o) => !o.current).map((o) => o.name).join(', ')}.',
    ].join(' ');
  }

  Future<String> setVolume(int level) async {
    final l = level.clamp(0, 100);
    await _out('/usr/bin/osascript', ['-e', 'set volume output volume $l without output muted']);
    return 'Volume is $l of 100.';
  }

  Future<String> mute(bool on) async {
    await _out('/usr/bin/osascript', ['-e', 'set volume ${on ? 'with' : 'without'} output muted']);
    return on ? 'Muted.' : 'Unmuted.';
  }

  /// Mutes the microphone by turning its level to 0; unmuting puts back the
  /// level it had.
  Future<String> muteMic(bool on) async {
    final v = await _volume();
    final now = int.tryParse(v['input volume'] ?? '') ?? 0;
    if (on) {
      if (now > 0) _micWas = now;
      await _out('/usr/bin/osascript', ['-e', 'set volume input volume 0']);
      return 'The microphone is muted.';
    }
    final back = now > 0 ? now : (_micWas ?? 75);
    await _out('/usr/bin/osascript', ['-e', 'set volume input volume $back']);
    return 'The microphone is on (level $back).';
  }

  /// The places sound can play through.
  Future<List<({String id, String name, bool current})>> outputs() async {
    final r = await _ask('outputs');
    return [
      for (final o in (r as List? ?? const []).whereType<Map>())
        (id: '${o['id']}', name: '${o['name']}', current: o['current'] == true),
    ];
  }

  /// Sends sound to the output whose name holds [name].
  Future<String> setOutput(String name) async {
    final all = await outputs();
    final want = name.toLowerCase().trim();
    final o =
        all.where((o) => o.name.toLowerCase() == want).firstOrNull ??
        all.where((o) => o.name.toLowerCase().contains(want)).firstOrNull;
    if (o == null) {
      throw MacTrouble(
        'There is no output called "$name". The outputs are: ${all.map((o) => o.name).join(', ')}.',
      );
    }
    if (await _ask('setOutput', {'id': int.parse(o.id)}) != true) {
      throw MacTrouble("${o.name} wouldn't take the sound.");
    }
    return 'Sound plays through ${o.name}.';
  }

  /// Presses a media key: play or pause, next, previous.
  Future<String> media(String key) async {
    final code = switch (key) {
      'play_pause' => 16,
      'next' => 17,
      'previous' => 18,
      _ => throw MacTrouble('No media key "$key": play_pause, next or previous.'),
    };
    await _ask('media', {'key': code});
    return switch (key) {
      'next' => 'Skipped to the next track.',
      'previous' => 'Went back a track.',
      _ => 'Pressed play/pause.',
    };
  }

  // What is using this Mac.

  /// What is working the processor and memory hardest now.
  Future<String> load() async {
    final ps = await _out('/bin/ps', ['-Aceo', 'pid=,pcpu=,rss=,comm=', '-r']);
    final top = <String>[];
    for (final line in const LineSplitter().convert(ps).take(8)) {
      final m = RegExp(r'^\s*(\d+)\s+([\d.]+)\s+(\d+)\s+(.+)$').firstMatch(line);
      if (m == null) continue;
      top.add('${m[4]} (pid ${m[1]}): ${m[2]}% of a core, ${_bytes(int.parse(m[3]!) * 1024)}');
    }
    final mem = await _out('/usr/bin/memory_pressure', ['-Q']).catchError((_) => '');
    final free = RegExp(r'(\d+)%').firstMatch(mem)?[1];
    final total = int.tryParse(await _out('/usr/sbin/sysctl', ['-n', 'hw.memsize']));
    final avg = await _out('/usr/sbin/sysctl', ['-n', 'vm.loadavg']);
    final cores = Platform.numberOfProcessors;
    return [
      'Load over the last minute: ${avg.replaceAll(RegExp(r'[{}]'), '').trim().split(' ').first} '
          '(this Mac has $cores cores).',
      if (free != null && total != null)
        'Memory: ${_bytes(total)} in all, $free% free by macOS\'s own measure.',
      'Hardest working now (processor use is averaged over the last moments):',
      ...top.map((t) => '- $t'),
    ].join('\n');
  }

  /// What is using the most energy, measured over a second.
  Future<String> energy() async {
    final out = await _out('/usr/bin/top', [
      '-l',
      '2',
      '-s',
      '1',
      '-o',
      'power',
      '-stats',
      'pid,command,power',
      '-n',
      '6',
    ]);
    // Two samples: the second is the one measured over the second.
    final lines = const LineSplitter().convert(out);
    final last = lines.lastIndexWhere((l) => l.trim().startsWith('PID'));
    final rows = <String>[];
    for (final l in lines.skip(last + 1)) {
      final m = RegExp(r'^\s*(\d+)\s+(.+?)\s+([\d.]+)\s*$').firstMatch(l);
      if (m != null) rows.add('- ${m[2]} (pid ${m[1]}): ${m[3]}');
    }
    return ['Using the most energy now (macOS\'s energy impact):', ...rows].join('\n');
  }

  // Battery.

  Future<String> battery() async {
    final batt = await _out('/usr/bin/pmset', ['-g', 'batt']);
    if (!batt.contains('InternalBattery')) return 'This Mac has no battery.';
    final source = RegExp(r"drawing from '([^']+)'").firstMatch(batt)?[1];
    final m = RegExp(r'(\d+)%;\s*([^;]+);\s*([^\s]+)').firstMatch(batt);
    final profile = await _out('/usr/sbin/system_profiler', [
      'SPPowerDataType',
    ]).catchError((_) => '');
    String? field(String name) => RegExp('$name: (.+)').firstMatch(profile)?[1]?.trim();
    final remaining = m?[3];
    return [
      if (m != null) 'Battery at ${m[1]}%, ${m[2]!.trim()}.',
      if (source != null) 'Running on ${source == 'AC Power' ? 'the charger' : 'battery'}.',
      if (remaining != null && remaining.contains(':') && remaining != '0:00')
        'About $remaining left${source == 'AC Power' ? ' until full' : ''}, as macOS estimates.',
      if (field('Maximum Capacity') case final c?) 'Health: holds $c of what it did new.',
      if (field('Cycle Count') case final c?) '$c charge cycles.',
      if (field('Condition') case final c?) 'macOS says its condition is $c.',
    ].join(' ');
  }

  // Disk.

  Future<String> disk() async {
    final out = await _out('/bin/df', ['-k', '/System/Volumes/Data']);
    final f = const LineSplitter().convert(out).last.split(RegExp(r'\s+'));
    final total = int.parse(f[1]) * 1024, free = int.parse(f[3]) * 1024;
    return '${_bytes(free)} free of ${_bytes(total)}. '
        '(Finder may show more: it also counts space macOS can clear on its own.)';
  }

  /// The biggest folders in [folder] (the home folder when null), measured.
  Future<String> biggest([String? folder]) async {
    final home = Platform.environment['HOME'] ?? '/';
    final dir = (folder == null || folder.trim().isEmpty)
        ? home
        : folder.trim().replaceFirst(RegExp(r'^~'), home);
    if (!Directory(dir).existsSync()) throw MacTrouble('There is no folder at $dir.');
    final r = await _run('/usr/bin/du', ['-d', '1', '-k', dir]).timeout(
      const Duration(minutes: 3),
      onTimeout: () =>
          throw const MacTrouble('Measuring took over three minutes; try a smaller folder.'),
    );
    final rows = <(int, String)>[];
    for (final l in const LineSplitter().convert('${r.stdout}')) {
      final m = RegExp(r'^(\d+)\s+(.+)$').firstMatch(l);
      if (m == null || m[2] == dir) continue;
      rows.add((int.parse(m[1]!) * 1024, m[2]!));
    }
    rows.sort((a, b) => b.$1.compareTo(a.$1));
    final unread =
        '${r.stderr}'.contains('Operation not permitted') ||
        '${r.stderr}'.contains('Permission denied');
    return [
      'Biggest in $dir:',
      for (final (size, path) in rows.take(12)) '- $path: ${_bytes(size)}',
      if (unread)
        "Some folders inside couldn't be read without Full Disk Access, so they count as less "
            'than they hold.',
    ].join('\n');
  }

  // Network.

  Future<String?> _wifiDevice() async {
    final out = await _out('/usr/sbin/networksetup', ['-listallhardwareports']);
    return RegExp(r'Hardware Port: Wi-Fi\nDevice: (\S+)').firstMatch(out)?[1];
  }

  Future<String> network() async {
    final dev = await _wifiDevice();
    final power = dev == null
        ? null
        : await _out('/usr/sbin/networksetup', ['-getairportpower', dev]);
    final ip = dev == null
        ? ''
        : (await _run('/usr/sbin/ipconfig', ['getifaddr', dev])).stdout.toString().trim();
    return [
      if (dev == null)
        'This Mac has no Wi-Fi.'
      else if (power!.endsWith('Off'))
        'Wi-Fi is off.'
      else if (ip.isEmpty)
        'Wi-Fi is on but not connected.'
      else
        'Wi-Fi is on and connected, at $ip on the local network. '
            "(macOS keeps the network's name from apps without the Location permission.)",
    ].join(' ');
  }

  Future<String> wifi(bool on) async {
    final dev = await _wifiDevice();
    if (dev == null) throw const MacTrouble('This Mac has no Wi-Fi.');
    await _out('/usr/sbin/networksetup', ['-setairportpower', dev, on ? 'on' : 'off']);
    return on ? 'Wi-Fi is on.' : 'Wi-Fi is off.';
  }

  /// Apple's own speed test: about 20 seconds.
  Future<String> speedTest() async {
    final out = await _out('/usr/bin/networkQuality', ['-c']);
    final j = jsonDecode(out) as Map;
    String mbps(Object? v) => v is num ? '${(v / 1e6).toStringAsFixed(0)} Mbps' : 'unknown';
    final rpm = j['responsiveness'] is num ? (j['responsiveness'] as num).round() : null;
    return 'Download ${mbps(j['dl_throughput'])}, upload ${mbps(j['ul_throughput'])}'
        '${rpm == null ? '' : ', responsiveness $rpm round trips a minute (${rpm >= 1000
                  ? 'high'
                  : rpm >= 300
                  ? 'medium'
                  : 'low'})'}. '
        "Measured just now with Apple's test.";
  }

  // Apps and drives.

  Future<String> apps() async {
    final r = await _ask('apps');
    final all = [for (final a in (r as List? ?? const []).whereType<Map>()) '${a['name']}'];
    return all.isEmpty ? 'No apps are open.' : 'Open apps: ${all.join(', ')}.';
  }

  /// Quits the app called [name]; [force] quits it without letting it save.
  Future<String> quit(String name, {bool force = false}) async {
    final r = await _ask('quit', {'name': name, 'force': force});
    if (r is String) throw MacTrouble(r);
    return force ? 'Force quit $name.' : 'Asked $name to quit.';
  }

  Future<String> drives() async {
    final r = await _ask('drives');
    final all = [for (final d in (r as List? ?? const [])) '$d'];
    return all.isEmpty ? 'No drives to eject.' : 'Drives that can be ejected: ${all.join(', ')}.';
  }

  /// Ejects every drive that can be.
  Future<String> eject() async {
    final r = await _ask('eject') as Map? ?? const {};
    final done = [for (final d in (r['ejected'] as List? ?? const [])) '$d'];
    final failed = [for (final d in (r['failed'] as List? ?? const [])) '$d'];
    if (done.isEmpty && failed.isEmpty) return 'There were no drives to eject.';
    return [
      if (done.isNotEmpty) 'Ejected ${done.join(', ')}.',
      if (failed.isNotEmpty)
        "Couldn't eject ${failed.join(', ')}: something is still using ${failed.length == 1 ? 'it' : 'them'}.",
    ].join(' ');
  }

  /// Shows or hides hidden files in Finder (Finder restarts to take it).
  Future<String> hiddenFiles(bool show) async {
    await _out('/usr/bin/defaults', [
      'write',
      'com.apple.finder',
      'AppleShowAllFiles',
      '-bool',
      '$show',
    ]);
    await _run('/usr/bin/killall', ['Finder']);
    return show ? 'Finder shows hidden files now.' : 'Finder hides hidden files again.';
  }

  static String _bytes(int b) {
    const units = ['bytes', 'KB', 'MB', 'GB', 'TB'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1000 && i < units.length - 1) {
      v /= 1000;
      i++;
    }
    return i == 0 ? '$b bytes' : '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _span(Duration d) {
    if (d.inMinutes < 1) return 'under a minute';
    final h = d.inHours, m = d.inMinutes % 60;
    return [
      if (h > 0) '$h hour${h == 1 ? '' : 's'}',
      if (m > 0) '$m minute${m == 1 ? '' : 's'}',
    ].join(' ');
  }
}
