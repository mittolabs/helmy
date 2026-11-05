import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A window to snapshot into the message being written, asked for by both
/// Shift keys or the composer's menu; the conversation on screen takes it.
final snapshotRequests = ValueNotifier<({ScreenWindow window, bool fromKeys})?>(null);

/// The panes of System Settings that grant what snapshots need.
const screenRecordingPane =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture';
const accessibilityPane =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility';

/// A window on screen that can be snapshotted.
typedef ScreenWindow = ({int id, int pid, String app, String title});

/// A snapshot taken: its picture, and the text in the window where macOS
/// gave it, both as files to attach.
typedef WindowShot = ({String picture, String? text, ScreenWindow window});

/// What macOS lets Helmy do for snapshots: see other apps' windows
/// (screen recording), and read what is in them and hear both Shift keys
/// anywhere (accessibility).
typedef SnapshotAccess = ({bool record, bool read});

/// SnapShots, as T3 Code has them: any app's window, captured into the
/// message being written, with the text in it where macOS gives it, so the
/// agent can read the window and not only look at it.
class WindowSnapshots {
  WindowSnapshots({required this._appData});
  final Future<Directory> Function() _appData;

  static const _channel = MethodChannel('helmy/notify');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    if (!Platform.isMacOS) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// The windows on screen, front to back, Helmy's own left out.
  Future<List<ScreenWindow>> windows() async {
    final list = await _call<List>('snapWindows') ?? const [];
    return [
      for (final w in list.whereType<Map>())
        (
          id: (w['id'] as num).toInt(),
          pid: (w['pid'] as num).toInt(),
          app: '${w['app']}',
          title: '${w['title'] ?? ''}',
        ),
    ];
  }

  Future<SnapshotAccess> access() async {
    final m = await _call<Map>('snapAllowed');
    return (record: m?['record'] == true, read: m?['read'] == true);
  }

  /// Asks macOS for screen recording; it shows its prompt the first time.
  Future<bool> askRecord() async => await _call<bool>('snapAskRecord') ?? false;

  /// Asks macOS for accessibility; it opens its prompt.
  Future<bool> askRead() async => await _call<bool>('snapAskRead') ?? false;

  /// Both Shift keys in any app take a snapshot: on or off. True when on
  /// and macOS lets Helmy hear them outside its own window.
  Future<bool> listen(bool on, {({String char, bool cmd, bool shift, bool alt})? also}) async =>
      await _call<bool>('snapKeys', {
        'on': on,
        if (also != null) ...{
          'char': also.char,
          'cmd': also.cmd,
          'shift': also.shift,
          'alt': also.alt,
        },
      }) ??
      false;

  /// Brings Helmy forward, after a snapshot taken in another app.
  Future<void> activate() => _call<void>('activate');

  /// Plays one of the system's sounds by [name]: Pop, Tink.
  Future<void> sound(String name) => _call<void>('playSound', {'name': name});

  /// Snapshots [w]: its picture, and its text where macOS gives it, saved
  /// as files named for the app and window. Null when it could not be taken
  /// (most often, screen recording not allowed).
  Future<WindowShot?> take(ScreenWindow w) async {
    final dir = Directory('${(await _appData()).path}/snapshots');
    await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final name = nameFor(w);
    final picture = '${dir.path}/$name $stamp.png';
    if (await _call<bool>('snapCapture', {'id': w.id, 'path': picture}) != true) return null;
    String? textPath;
    final text = await _call<String>('snapText', {'pid': w.pid, 'title': w.title});
    if (text != null && saysMore(text, w)) {
      textPath = '${dir.path}/$name $stamp.md';
      await File(textPath).writeAsString(textOf(w, text));
    }
    return (picture: picture, text: textPath, window: w);
  }

  /// Whether a window's text says more than its own name: some apps give
  /// only that (a Flutter app, until a screen reader asks), and a file of it
  /// would only be noise beside the picture.
  static bool saysMore(String outline, ScreenWindow w) {
    final words = outline
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^\s*- [^:]*: ?'), '').trim())
        .where((l) => l.isNotEmpty && l != w.app && l != w.title)
        .toList();
    return words.length >= 3;
  }

  /// A file name for [w]: its app and title, safe for a file system.
  static String nameFor(ScreenWindow w) {
    final raw = w.title.trim().isEmpty ? w.app : '${w.app}, ${w.title}';
    final safe = raw.replaceAll(RegExp(r'[/\\:*?"<>|\n\r]'), '-').trim();
    return safe.length <= 80 ? safe : safe.substring(0, 80).trim();
  }

  /// The window's text as a file the agent reads beside its picture.
  static String textOf(ScreenWindow w, String outline) =>
      '# ${w.app}${w.title.isEmpty ? '' : ': ${w.title}'}\n\n'
      'What this window holds, read from it as the screen reader reads it: each '
      'line is a part of the window (its role) and the words in it.\n\n$outline\n';
}
