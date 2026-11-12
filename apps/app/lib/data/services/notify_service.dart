import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../ui/core/window_layout.dart';

/// System notifications and the dock badge, through the macOS runner
/// (`MainFlutterWindow.swift`).
/// Counts presses of About Helmy in the app's menu.
final aboutRequests = ValueNotifier<int>(0);

/// Words heard by dictation as they come, and whether they are all.
final dictation = StreamController<({String text, bool last})>.broadcast();

/// Words said aloud have ended (true) or were cut short (false).
final spoken = StreamController<bool>.broadcast();

/// Counts presses of Help, Show the Tour.
final tourRequests = ValueNotifier<int>(0);

/// Counts ⌘Q pressed once while chats work, held back for a second press.
final quitAsked = ValueNotifier<int>(0);

class NotifyService {
  new() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) _opened.add(call.arguments as String);
      if (call.method == 'fullScreen') windowFullScreen.value = call.arguments == true;
      if (call.method == 'inSight') _inSight.add(call.arguments == true);
      if (call.method == 'about') aboutRequests.value++;
      if (call.method == 'tour') tourRequests.value++;
      if (call.method == 'dictation' && call.arguments is Map) {
        final a = call.arguments as Map;
        dictation.add((text: '${a['text'] ?? ''}', last: a['final'] == true));
      }
      if (call.method == 'spoken') spoken.add(call.arguments == true);
      if (call.method == 'quitAsked') quitAsked.value++;
      if (call.method == 'snapshot' && call.arguments is Map) {
        _snapshots.add((call.arguments as Map).cast<String, Object?>());
      }
    });
  }

  static const _channel = MethodChannel('helmy/notify');
  final _opened = StreamController<String>.broadcast();
  final _inSight = StreamController<bool>.broadcast();
  final _snapshots = StreamController<Map<String, Object?>>.broadcast();

  /// Both Shift keys pressed (snapshots on): the window that was in front.
  Stream<Map<String, Object?>> get snapshotKeys => _snapshots.stream;

  /// The window coming into sight (focused, showing) or going out of it.
  Stream<bool> get inSight => _inSight.stream;

  /// Whether the system lets Helmy notify; null when it cannot be asked.
  Future<bool?> notificationsAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('notificationsAllowed');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Takes [sessionId]'s notification out of the system's list, once seen.
  Future<void> clearNotification(String sessionId) =>
      _call('clearNotification', {'sessionId': sessionId});

  /// Sessions whose notification was clicked.
  Stream<String> get opened => _opened.stream;

  /// The ID Windows knows Helmy by, set on its Start menu shortcut by the
  /// installer: notifications shown under it read as Helmy's.
  static const windowsAppId = 'Mittolabs.Helmy';

  /// With [thumbsUp], Helmy giving a thumbs up rides along: work done well.
  /// The system's own notification on each: macOS's, Windows' toasts,
  /// and the desktop's on Linux (through notify-send).
  Future<void> notify({
    required String sessionId,
    required String title,
    required String body,
    bool thumbsUp = false,
    bool banner = true,
    bool sound = true,
  }) async {
    if (Platform.isLinux) return _linux(sessionId, title, body);
    if (Platform.isWindows) return _windows(title, body, sound: sound);
    await _call('notify', {
      'sessionId': sessionId,
      'title': title,
      'body': body,
      'thumbsUp': thumbsUp,
      'banner': banner,
      'sound': sound,
    });
  }

  /// notify-send, with an Open action: chosen, it opens the chat. Older
  /// notify-send without actions shows it plainly.
  Future<void> _linux(String sessionId, String title, String body) async {
    try {
      final p = await Process.start('notify-send', [
        '--app-name=Helmy',
        '--action=open=Open',
        '--wait',
        title,
        body,
      ]);
      unawaited(
        p.stdout.transform(const SystemEncoding().decoder).join().then((out) {
          if (out.trim() == 'open') _opened.add(sessionId);
        }),
      );
      if (await p.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => 0) != 0) {
        await Process.run('notify-send', ['--app-name=Helmy', title, body]);
      }
    } on Object {
      // No notification service on this desktop: nothing to show it with.
    }
  }

  /// A toast through Windows' own notifications, under Helmy's app ID.
  Future<void> _windows(String title, String body, {required bool sound}) async {
    String xml(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
    final toast =
        '<toast><visual><binding template="ToastGeneric"><text>${xml(title)}</text>'
        '<text>${xml(body)}</text></binding></visual>${sound ? '' : '<audio silent="true"/>'}</toast>';
    final script =
        r'[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null;'
        r'[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null;'
        r'$x = New-Object Windows.Data.Xml.Dom.XmlDocument; $x.LoadXml($env:HELMY_TOAST);'
        '[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("$windowsAppId")'
        r'.Show([Windows.UI.Notifications.ToastNotification]::new($x))';
    try {
      await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', script],
        environment: {'HELMY_TOAST': toast},
      );
    } on Object {
      // No PowerShell: nothing to show it with.
    }
  }

  /// Whether the first ⌘Q only warns: on while chats work, if so set.
  Future<void> quitGuard(bool on) => _call('quitGuard', {'on': on});

  /// Whether the app is in front, as macOS says; null when it cannot be asked.
  Future<bool?> isActive() async {
    try {
      return await _channel.invokeMethod<bool>('isActive');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> badge(int count) => _call('badge', {'count': count});

  /// Shows Helmy's [face] in the Dock (`waking`, `thinking`, `answering`,
  /// `needs-you`, `background`, `done`, `error`, `offline`, `dozing`), or the app
  /// icon when null.
  Future<void> face(String? face) => _call('face', {'face': face});

  /// Says on the splash what Helmy is doing as it starts.
  static Future<void> splash(String text) async {
    try {
      await _channel.invokeMethod<void>('splash', {'text': text});
    } on Object {
      // Not on macOS, or in a test: there is no splash.
    }
  }

  /// Tells macOS the app has drawn its first frame, so the splash window
  /// hands over to the main one.
  /// Static, so calling it never takes over the channel's handler.
  static Future<void> ready() async {
    try {
      await _channel.invokeMethod<void>('ready');
    } on Object {
      // Not on macOS, or in a test: there is no splash to dismiss.
    }
  }

  Future<void> _call(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No runner to talk to, as in tests: nothing to show.
    } on PlatformException {
      // Notifications refused or unavailable; the app works without them.
    }
  }
}
