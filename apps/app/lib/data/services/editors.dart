import 'dart:io';

import 'package:flutter/services.dart';

import 'cli_locator.dart';

/// What an app that can open a project is for.
enum EditorKind {
  /// A code editor: opens the folder.
  editor,

  /// An IDE for one platform (Xcode, Android Studio): opens the project it
  /// understands, and is offered only for those projects.
  ide,

  /// A terminal, at the folder.
  terminal,
}

/// An app on this computer that can open a project.
class Editor {
  const Editor({
    required this.id,
    required this.name,
    required this.path,
    required this.kind,
    this.icon,
    this.lastUsed,
  });

  /// Its bundle id (the Mac's, for the same app found elsewhere too).
  final String id;
  final String name;
  final String path;
  final EditorKind kind;

  /// Its icon, as macOS draws it.
  final Uint8List? icon;

  /// When it was last used, as macOS recorded it.
  final DateTime? lastUsed;
}

/// The apps Helmy can open a project in, in the order they are offered when
/// none has been used: the editors people use most for code first.
const knownEditors = <(String, EditorKind)>[
  ('com.microsoft.VSCode', .editor),
  ('com.todesktop.230313mzl4w4u92', .editor), // Cursor
  ('dev.zed.Zed', .editor),
  ('com.exafunction.windsurf', .editor),
  ('com.microsoft.VSCodeInsiders', .editor),
  ('com.vscodium', .editor),
  ('com.sublimetext.4', .editor),
  ('com.panic.Nova', .editor),
  ('com.jetbrains.intellij', .editor),
  ('com.jetbrains.intellij.ce', .editor),
  ('com.jetbrains.WebStorm', .editor),
  ('com.jetbrains.pycharm', .editor),
  ('com.jetbrains.goland', .editor),
  ('com.jetbrains.rustrover', .editor),
  ('com.apple.dt.Xcode', .ide),
  ('com.google.android.studio', .ide),
  ('com.mitchellh.ghostty', .terminal),
  ('com.googlecode.iterm2', .terminal),
  ('dev.warp.Warp-Stable', .terminal),
  ('com.apple.Terminal', .terminal),
];

/// The same apps on Windows and Linux, found by their command: (id, name,
/// command, kind, and how a terminal is told the folder). VS Code and those
/// built on it put their command on the PATH when installed; JetBrains' come
/// with the Toolbox's shell scripts.
const otherDesktopEditors = <(String, String, String, EditorKind, String?)>[
  ('com.microsoft.VSCode', 'Visual Studio Code', 'code', .editor, null),
  ('com.todesktop.230313mzl4w4u92', 'Cursor', 'cursor', .editor, null),
  ('dev.zed.Zed', 'Zed', 'zed', .editor, null),
  ('dev.zed.Zed', 'Zed', 'zeditor', .editor, null),
  ('com.exafunction.windsurf', 'Windsurf', 'windsurf', .editor, null),
  ('com.microsoft.VSCodeInsiders', 'VS Code Insiders', 'code-insiders', .editor, null),
  ('com.vscodium', 'VSCodium', 'codium', .editor, null),
  ('com.sublimetext.4', 'Sublime Text', 'subl', .editor, null),
  ('com.jetbrains.intellij', 'IntelliJ IDEA', 'idea', .editor, null),
  ('com.jetbrains.WebStorm', 'WebStorm', 'webstorm', .editor, null),
  ('com.jetbrains.pycharm', 'PyCharm', 'pycharm', .editor, null),
  ('com.jetbrains.goland', 'GoLand', 'goland', .editor, null),
  ('com.jetbrains.rustrover', 'RustRover', 'rustrover', .editor, null),
  ('com.google.android.studio', 'Android Studio', 'studio', .ide, null),
  // Terminals, each told the folder its own way.
  ('com.microsoft.WindowsTerminal', 'Windows Terminal', 'wt', .terminal, '-d'),
  ('com.mitchellh.ghostty', 'Ghostty', 'ghostty', .terminal, '--working-directory='),
  ('org.gnome.Terminal', 'Terminal', 'gnome-terminal', .terminal, '--working-directory='),
  ('org.gnome.Ptyxis', 'Terminal', 'ptyxis', .terminal, '--working-directory='),
  ('org.kde.konsole', 'Konsole', 'konsole', .terminal, '--workdir'),
];

/// How [editor] is started off a Mac to open [target]: its command, then
/// the folder (a terminal's own way, as [otherDesktopEditors] says).
List<String> openArgs(String id, String command, String target) {
  final how = otherDesktopEditors.where((e) => e.$1 == id && e.$3 == command).firstOrNull?.$5;
  return switch (how) {
    null => [target],
    final flag when flag.endsWith('=') => ['$flag$target'],
    final flag => [flag, target],
  };
}

/// Finds the apps on this computer that can open a project, and opens one
/// there: asked of macOS on a Mac, found by command on Windows and Linux.
class EditorService {
  EditorService({this._locator});
  static const _channel = MethodChannel('helmy/notify');
  final CliLocator? _locator;

  Future<List<Editor>>? _installed;

  /// Every known app installed here, looked for once.
  Future<List<Editor>> installed() => _installed ??= () async {
    if (!Platform.isMacOS) return foundByCommand();
    try {
      final found = await _channel.invokeListMethod<Map>('apps', {
        'ids': [for (final (id, _) in knownEditors) id],
      });
      final kinds = {for (final (id, kind) in knownEditors) id: kind};
      return [
        for (final a in found ?? const <Map>[])
          Editor(
            id: a['id'] as String,
            name: a['name'] as String,
            path: a['path'] as String,
            kind: kinds[a['id']] ?? .editor,
            icon: a['icon'] as Uint8List?,
            lastUsed: a['lastUsed'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch((a['lastUsed'] as num).toInt()),
          ),
      ];
    } on Object {
      _installed = null;
      return const <Editor>[];
    }
  }();

  /// Off a Mac: the known apps whose command is on the PATH, one each.
  Future<List<Editor>> foundByCommand() async {
    final locator = _locator ?? CliLocator();
    final out = <Editor>[];
    for (final (id, name, command, kind, _) in otherDesktopEditors) {
      if (out.any((e) => e.id == id)) continue;
      if (await locator.find(command) case final path?) {
        out.add(Editor(id: id, name: name, path: path, kind: kind));
      }
    }
    return out;
  }

  /// Opens [folder] (or a file) in [editor]: an IDE opens the project in it
  /// it knows.
  Future<bool> open(Editor editor, String folder) async {
    final target = editor.kind == .ide && Directory(folder).existsSync()
        ? ideProject(editor.id, folder) ?? folder
        : folder;
    try {
      if (Platform.isMacOS) {
        final r = await Process.run('/usr/bin/open', ['-a', editor.path, target]);
        return r.exitCode == 0;
      }
      // Started on its own, to outlive the call; a .cmd needs the shell.
      final command = editor.path.split(RegExp(r'[/\\]')).last.split('.').first;
      await Process.start(
        editor.path,
        openArgs(editor.id, command, target),
        mode: ProcessStartMode.detached,
        runInShell: Platform.isWindows && editor.path.toLowerCase().endsWith('.cmd'),
        workingDirectory: Directory(target).existsSync() ? target : null,
      );
      return true;
    } on Object {
      return false;
    }
  }
}

/// What an IDE opens for [folder]: Xcode the workspace or project (a
/// Flutter or React Native app's is in ios/), Android Studio the Android
/// project (android/ in those apps); null when there is none for it.
String? ideProject(String id, String folder) {
  if (id == 'com.apple.dt.Xcode') {
    for (final dir in [folder, '$folder/ios', '$folder/macos']) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      final names = [for (final e in d.listSync()) e.path];
      final ws = names.where((p) => p.endsWith('.xcworkspace')).firstOrNull;
      if (ws != null) return ws;
      final proj = names.where((p) => p.endsWith('.xcodeproj')).firstOrNull;
      if (proj != null) return proj;
      if (File('$dir/Package.swift').existsSync()) return '$dir/Package.swift';
    }
    return null;
  }
  if (id == 'com.google.android.studio') {
    for (final dir in [folder, '$folder/android']) {
      for (final f in [
        'settings.gradle',
        'settings.gradle.kts',
        'build.gradle',
        'build.gradle.kts',
      ]) {
        if (File('$dir/$f').existsSync()) return dir;
      }
    }
    return null;
  }
  return null;
}

/// The apps to offer for [folder] from [installed]: IDEs only for the
/// projects they open; editors first, terminals last.
List<Editor> editorsFor(String folder, List<Editor> installed) => [
  for (final kind in EditorKind.values)
    for (final e in installed)
      if (e.kind == kind && (kind != .ide || ideProject(e.id, folder) != null)) e,
];

/// The app a project opens in by default: the one chosen last ([chosen], a
/// bundle id), else the editor used most recently, else the first editor.
Editor? defaultEditor(List<Editor> offered, String? chosen) {
  if (offered.isEmpty) return null;
  final picked = offered.where((e) => e.id == chosen).firstOrNull;
  if (picked != null) return picked;
  final editors = offered.where((e) => e.kind == .editor).toList();
  if (editors.isEmpty) return offered.first;
  final used = editors.where((e) => e.lastUsed != null).toList()
    ..sort((a, b) => b.lastUsed!.compareTo(a.lastUsed!));
  return used.firstOrNull ?? editors.first;
}
