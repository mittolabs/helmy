import 'dart:io';

import 'package:flutter/services.dart';

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

  /// Its bundle id.
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

/// Finds the apps on this Mac that can open a project, and opens one there.
class EditorService {
  static const _channel = MethodChannel('helmy/notify');

  Future<List<Editor>>? _installed;

  /// Every known app installed here, asked of macOS once.
  Future<List<Editor>> installed() => _installed ??= () async {
    if (!Platform.isMacOS) return const <Editor>[];
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

  /// Opens [folder] in [editor]: an IDE opens the project in it it knows.
  Future<bool> open(Editor editor, String folder) async {
    final target = editor.kind == .ide ? ideProject(editor.id, folder) ?? folder : folder;
    try {
      final r = await Process.run('/usr/bin/open', ['-a', editor.path, target]);
      return r.exitCode == 0;
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
