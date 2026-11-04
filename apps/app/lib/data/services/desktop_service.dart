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
