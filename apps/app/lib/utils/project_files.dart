import 'dart:io';

/// The files in [cwd], relative to it, for @ to pick from: what git tracks and
/// does not ignore, or a short walk that skips hidden and dependency folders.
Future<List<String>> projectFiles(String cwd, {int limit = 5000}) async {
  try {
    final git = await Process.run('git', [
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
    ], workingDirectory: cwd).timeout(const Duration(seconds: 5));
    if (git.exitCode == 0) {
      return (git.stdout as String).split('\n').where((l) => l.isNotEmpty).take(limit).toList();
    }
  } on Object {
    // Not a git folder, or no git: walk instead.
  }
  final out = <String>[];
  const skip = {'node_modules', 'build', 'dist', 'Pods', 'DerivedData', 'Library', '.dart_tool'};
  void walk(Directory dir, String rel, int depth) {
    if (depth > 4 || out.length >= limit) return;
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync();
    } on FileSystemException {
      return;
    }
    for (final e in entries) {
      final name = e.path.split('/').last;
      if (name.startsWith('.') || skip.contains(name)) continue;
      final path = rel.isEmpty ? name : '$rel/$name';
      if (e is Directory) {
        walk(e, path, depth + 1);
      } else {
        out.add(path);
      }
      if (out.length >= limit) return;
    }
  }

  walk(Directory(cwd), '', 0);
  return out;
}

/// The best few of [all] for what was typed: names that start with it first,
/// then paths that hold it, shortest first.
List<String> fuzzyPick(List<String> all, String typed, {int count = 8}) {
  final q = typed.toLowerCase();
  if (q.isEmpty) return all.take(count).toList();
  int score(String p) {
    final name = p.split('/').last.toLowerCase();
    if (name.startsWith(q)) return 0;
    if (name.contains(q)) return 1;
    if (p.toLowerCase().contains(q)) return 2;
    return 9;
  }

  final hits =
      [
        for (final p in all)
          if (score(p) < 9) p,
      ]..sort((a, b) {
        final s = score(a).compareTo(score(b));
        return s != 0 ? s : a.length.compareTo(b.length);
      });
  return hits.take(count).toList();
}
