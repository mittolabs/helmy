import 'dart:async';

import 'package:flutter/services.dart';

/// This Mac's screen as frames, and a way to use it: what [RemoteServer]
/// shows a paired phone. Frames come one at a time, the next only once
/// [next] asks, so a slow phone gets fewer frames rather than late ones.
abstract class ScreenSource {
  /// Starts sharing, with [mark] in the bar that says so. Null when it
  /// started; else "record" (Screen Recording not allowed) or what went wrong.
  Future<String?> start({required String mark});

  /// Asks for the next frame.
  void next();

  Future<void> stop();

  /// A touch or key from the phone. Null when done; "accessibility" when
  /// Helmy may not post input.
  Future<String?> input(Map<String, Object?> args);

  /// Each frame, as JPEG.
  void Function(Uint8List jpeg)? onFrame;

  /// Sharing stopped on the Mac: its Stop pressed, or the capture ended.
  void Function(String why)? onStopped;
}

/// The Mac's own, through `helmy/screen` in MainFlutterWindow.swift.
class MacScreen implements ScreenSource {
  MacScreen() {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'frame':
          if (call.arguments case final Uint8List b) onFrame?.call(b);
        case 'stopped':
          onStopped?.call('${call.arguments ?? ''}');
      }
    });
  }

  static const _ch = MethodChannel('helmy/screen');

  @override
  void Function(Uint8List jpeg)? onFrame;

  @override
  void Function(String why)? onStopped;

  @override
  Future<String?> start({required String mark}) async {
    try {
      return await _ch.invokeMethod<String>('start', {'mark': mark, 'maxWidth': 1600, 'fps': 12});
    } on PlatformException catch (e) {
      return e.message ?? 'The screen could not be shared.';
    } on MissingPluginException {
      return 'This computer cannot share its screen.';
    }
  }

  @override
  void next() => unawaited(_ch.invokeMethod<void>('next').catchError((_) {}));

  @override
  Future<void> stop() async {
    try {
      await _ch.invokeMethod<void>('stop');
    } on Object {
      // Nothing was being shared.
    }
  }

  @override
  Future<String?> input(Map<String, Object?> args) async {
    try {
      return await _ch.invokeMethod<String>('input', args);
    } on Object catch (e) {
      return '$e';
    }
  }

  /// Whether Helmy may record the screen and post input, for Settings.
  static Future<({bool record, bool control})> allowed() async {
    try {
      final r = await _ch.invokeMapMethod<String, Object?>('allowed') ?? const {};
      return (record: r['record'] == true, control: r['control'] == true);
    } on Object {
      return (record: false, control: false);
    }
  }

  /// Asks macOS for Screen Recording (its own prompt the first time).
  static Future<void> askRecord() async {
    try {
      await _ch.invokeMethod<bool>('askRecord');
    } on Object {
      // Settings opens the pane instead.
    }
  }
}
