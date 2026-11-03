import 'dart:io';

import 'package:flutter/services.dart';

/// What the desktop does with a file: copy a picture, open it in its app,
/// show it in Finder.
class DesktopService {
  static const _channel = MethodChannel('helmy/notify');

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

  /// Whether closing the window hides it (sessions keep working) or quits.
  Future<void> setKeepRunning(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepRunning', {'on': on});
    } on MissingPluginException {
      // No runner, as in tests.
    }
  }

  /// Whether Helmy opens at login, after turning it [on] or off when given;
  /// null when this macOS cannot say.
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

  /// Opens [path] in the app macOS uses for it.
  Future<void> open(String path) => Process.run('/usr/bin/open', [path]);

  /// Shows [path] selected in a Finder window.
  Future<void> reveal(String path) => Process.run('/usr/bin/open', ['-R', path]);
}

extension on int {
  int let(int Function(int) f) => f(this);
}
