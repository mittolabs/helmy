import 'dart:async';

import 'package:flutter/services.dart';

import '../../ui/core/window_layout.dart';

/// System notifications and the dock badge, through the macOS runner
/// (`MainFlutterWindow.swift`).
class NotifyService {
  new() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) _opened.add(call.arguments as String);
      if (call.method == 'fullScreen') windowFullScreen.value = call.arguments == true;
      if (call.method == 'inSight') _inSight.add(call.arguments == true);
    });
  }

  static const _channel = MethodChannel('helmy/notify');
  final _opened = StreamController<String>.broadcast();
  final _inSight = StreamController<bool>.broadcast();

  /// The window coming into sight (focused, showing) or going out of it.
  Stream<bool> get inSight => _inSight.stream;

  /// Takes [sessionId]'s notification out of the system's list, once seen.
  Future<void> clearNotification(String sessionId) =>
      _call('clearNotification', {'sessionId': sessionId});

  /// Sessions whose notification was clicked.
  Stream<String> get opened => _opened.stream;

  /// With [thumbsUp], Helmy giving a thumbs up rides along: work done well.
  Future<void> notify({
    required String sessionId,
    required String title,
    required String body,
    bool thumbsUp = false,
  }) =>
      _call('notify', {'sessionId': sessionId, 'title': title, 'body': body, 'thumbsUp': thumbsUp});

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
