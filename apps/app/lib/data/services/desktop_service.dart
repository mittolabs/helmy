import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/platform.dart';

/// What the desktop does with a file: copy a picture, open it in its app,
/// show it in Finder.
class DesktopService {
  static const _channel = MethodChannel('helmy/notify');

  final _pictures = <String, Future<String?>>{};

  /// A picture of a document's first page, by Quick Look, made once into a
  /// temporary folder; null where there is no Quick Look (off a Mac) or it
  /// could not make one.
  Future<String?> documentPicture(String path) => _pictures[path] ??= () async {
    if (!Desktop.current.documentPictures) return null;
    try {
      final out = await Directory.systemTemp.createTemp('helmy-look');
      final r = await Process.run('/usr/bin/qlmanage', ['-t', '-s', '900', '-o', out.path, path]);
      if (r.exitCode != 0) return null;
      return out.listSync().whereType<File>().firstOrNull?.path;
    } on Object {
      return null;
    }
  }();

  /// [path]'s words as plain text (RTF, Word, Pages and the like), by
  /// macOS's textutil; null where that cannot read it.
  Future<String?> documentText(String path) async {
    if (!Platform.isMacOS) return null;
    try {
      final r = await Process.run('/usr/bin/textutil', ['-convert', 'txt', '-stdout', path]);
      return r.exitCode == 0 ? r.stdout as String : null;
    } on Object {
      return null;
    }
  }

  /// Puts the picture at [path] on the clipboard. False when it could not.
  Future<bool> copyImage(String path) async {
    try {
      return await _channel.invokeMethod<bool>('copyImage', {'path': path}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Saves a picture on the clipboard to [path] as PNG and returns it; null
  /// when the clipboard holds no picture.
  Future<String?> pasteImage(String path) async {
    try {
      return await _channel.invokeMethod<String>('pasteImage', {'path': path});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Does [action] to the page in the Preview panel ('inspect', 'zoom',
  /// 'hardReload', 'appearance'); false where it cannot.
  Future<bool> webPage(String action, [Map<String, Object?> args = const {}]) async {
    if (Desktop.current != .mac) return false;
    try {
      return await _channel.invokeMethod<bool>('webPage', {'do': action, ...args}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Saves a picture of the page in the Preview panel (the built-in browser)
  /// to [path], as PNG; the path, or null where it cannot.
  Future<String?> webSnapshot(String path) async {
    if (Desktop.current != .mac) return null;
    try {
      return await _channel.invokeMethod<String>('webSnapshot', {'path': path});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// The first run's window, small and of one size, when [on]; the usual
  /// one, resizable, when not. Static: it is set before the app runs.
  static Future<void> compactWindow(bool on) async {
    try {
      await _channel.invokeMethod<void>('compactWindow', {'on': on});
    } on Object {
      // No runner, as in tests, or not macOS: the window stays as it is.
    }
  }

  /// Whether closing the window hides it (sessions keep working) or quits:
  /// as last set, for the main window's close button.
  static bool keepRunning = true;

  /// Hides the main window: its close button with [keepRunning] on.
  static Future<void> hideMainWindow() async {
    try {
      await _channel.invokeMethod<void>('hideMain');
    } on Object {
      // No runner, as in tests.
    }
  }

  /// Whether closing the window hides it (sessions keep working) or quits.
  Future<void> setKeepRunning(bool on) async {
    keepRunning = on;
    try {
      await _channel.invokeMethod<void>('keepRunning', {'on': on});
    } on MissingPluginException {
      // No runner, as in tests.
    }
  }

  /// Whether Helmy opens at login, after turning it [on] or off when given;
  /// null when this macOS cannot say.
  /// The programs Helmy started that are still running (its connections,
  /// browsers, terminals), with their CPU share and memory, from `ps`.
  Future<List<({int pid, String name, String command, double cpu, int bytes})>>
  helmysProcesses() async {
    if (Platform.isWindows) return const [];
    try {
      final r = await Process.run('/bin/ps', ['-axo', 'pid=,ppid=,%cpu=,rss=,command=']);
      final rows = <int, ({int ppid, double cpu, int kb, String command})>{};
      for (final line in '${r.stdout}'.split('\n')) {
        final m = RegExp(r'^\s*(\d+)\s+(\d+)\s+([\d.]+)\s+(\d+)\s+(.*)$').firstMatch(line);
        if (m == null) continue;
        rows[int.parse(m[1]!)] = (
          ppid: int.parse(m[2]!),
          cpu: double.parse(m[3]!),
          kb: int.parse(m[4]!),
          command: m[5]!,
        );
      }
      // Helmy's own children, and theirs.
      final mine = <int>{pid};
      var grew = true;
      while (grew) {
        grew = false;
        for (final e in rows.entries) {
          if (!mine.contains(e.key) && mine.contains(e.value.ppid)) {
            mine.add(e.key);
            grew = true;
          }
        }
      }
      mine.remove(pid);
      // Not the ps that was just asked.
      mine.removeWhere((id) => rows[id]?.command.startsWith('/bin/ps ') ?? false);
      final out = [
        for (final id in mine)
          if (rows[id] case final p?)
            (
              pid: id,
              name: _programName(p.command),
              command: p.command,
              cpu: p.cpu,
              bytes: p.kb * 1024,
            ),
      ]..sort((a, b) => b.bytes.compareTo(a.bytes));
      return out;
    } on Object {
      return const [];
    }
  }

  static String _programName(String command) {
    final exe = command.split(' ').first.split('/').last;
    if (command.contains('--user-data-dir=') && command.contains('/chromium/profiles/')) {
      return 'Browser for the Preview panel';
    }
    return exe.isEmpty ? command : exe;
  }

  /// Stops [processId], one of [helmysProcesses]; true when it was asked to.
  Future<bool> stopProcess(int processId) async {
    final ours = await helmysProcesses();
    if (!ours.any((p) => p.pid == processId)) return false;
    return Process.killPid(processId);
  }

  /// The font families installed, by name, and those of them whose letters
  /// are all one width (for code). Empty where the system will not say.
  Future<({List<String> all, List<String> fixed})> fontFamilies() async {
    if (!Platform.isMacOS) return (all: const <String>[], fixed: const <String>[]);
    try {
      final r = await Process.run('/usr/bin/osascript', [
        '-l',
        'JavaScript',
        '-e',
        'ObjC.import("AppKit"); var m = \$.NSFontManager.sharedFontManager; '
            'var all = m.availableFontFamilies.js.map(x => x.js).filter(n => !n.startsWith(".")); '
            'var fixed = all.filter(n => { var f = \$.NSFont.fontWithNameSize(n, 12); '
            'return f && f.isFixedPitch; }); JSON.stringify({all: all, fixed: fixed})',
      ]).timeout(const Duration(seconds: 15));
      final j = jsonDecode('${r.stdout}'.trim()) as Map;
      return (
        all: [...(j['all'] as List).map((x) => '$x')],
        fixed: [...(j['fixed'] as List).map((x) => '$x')],
      );
    } on Object {
      return (all: const <String>[], fixed: const <String>[]);
    }
  }

  Future<bool?> openAtLogin([bool? on]) async {
    try {
      return await _channel.invokeMethod<bool>('openAtLogin', {'on': on});
    } on MissingPluginException {
      return null;
    }
  }

  /// How much space a folder takes, from du; null when it is not there.
  Future<int?> sizeOf(String path) async {
    if (!Directory(path).existsSync() && !File(path).existsSync()) return null;
    try {
      final r = await Process.run('du', ['-sk', path]).timeout(const Duration(seconds: 30));
      return int.tryParse('${r.stdout}'.split(RegExp(r'\s')).first)?.let((kb) => kb * 1024);
    } on Object {
      return null;
    }
  }

  /// Opens [path] (a file or a web address) in the app the computer uses
  /// for it.
  Future<void> open(String path) => switch (Desktop.current) {
    .mac => Process.run('/usr/bin/open', [path]),
    // `start` treats its first quoted argument as a window title.
    .windows => Process.run('cmd', ['/c', 'start', '', path]),
    .linux => Process.run('xdg-open', [path]),
  };

  /// Shows [path] selected in the file manager (Finder, File Explorer); on
  /// Linux, whose file managers differ, its folder opens.
  Future<void> reveal(String path) => switch (Desktop.current) {
    .mac => Process.run('/usr/bin/open', ['-R', path]),
    .windows => Process.run('explorer', ['/select,', path]),
    .linux => Process.run('xdg-open', [File(path).parent.path]),
  };
}

extension on int {
  int let(int Function(int) f) => f(this);
}
