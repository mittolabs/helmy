import 'dart:async';

import 'package:flutter/services.dart';

/// System notifications and the dock badge, through the macOS runner
/// (`MainFlutterWindow.swift`).
class NotifyService {
  new() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) _opened.add(call.arguments as String);
    });
  }

  static const _channel = MethodChannel('helmy/notify');
  final _opened = StreamController<String>.broadcast();

  /// Sessions whose notification was clicked.
  Stream<String> get opened => _opened.stream;

  Future<void> notify({required String sessionId, required String title, required String body}) =>
      _call('notify', {'sessionId': sessionId, 'title': title, 'body': body});

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
