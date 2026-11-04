/// One row of a file tree as it shows: a folder or a file, how deep, and
/// for a folder whether it is open.
typedef FileRow = ({String path, String name, int depth, bool folder, bool open});

/// The rows of the tree of [paths] (files, relative, "/" between folders)
/// that show with the folders in [open] open: folders first, then files,
/// each by name as people sort them (case aside). A folder holding only one
/// folder shows as one row, "src/main", as editors do.
List<FileRow> visibleRows(List<String> paths, Set<String> open) {
  final root = _Node('');
  for (final p in paths) {
    var node = root;
    final parts = p.split('/');
    for (var i = 0; i < parts.length; i++) {
      final name = parts[i];
      if (name.isEmpty) continue;
      final path = parts.take(i + 1).join('/');
      final last = i == parts.length - 1;
      node = (last ? node.files : node.folders).putIfAbsent(name, () => _Node(path));
    }
  }
  final out = <FileRow>[];
  int byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  void walk(_Node node, int depth) {
    for (final name in node.folders.keys.toList()..sort(byName)) {
      var child = node.folders[name]!;
      var label = name;
      // Folders that hold just one folder join it: "lib/src".
      while (child.files.isEmpty && child.folders.length == 1) {
        final only = child.folders.entries.single;
        label = '$label/${only.key}';
        child = only.value;
      }
      final isOpen = open.contains(child.path);
      out.add((path: child.path, name: label, depth: depth, folder: true, open: isOpen));
      if (isOpen) walk(child, depth + 1);
    }
    for (final name in node.files.keys.toList()..sort(byName)) {
      out.add((path: node.files[name]!.path, name: name, depth: depth, folder: false, open: false));
    }
  }

  walk(root, 0);
  return out;
}

/// The folders that hold [path], so it shows when they are open.
Iterable<String> foldersOf(String path) sync* {
  final parts = path.split('/');
  for (var i = 1; i < parts.length; i++) {
    yield parts.take(i).join('/');
  }
}

class _Node {
  _Node(this.path);
  final String path;
  final folders = <String, _Node>{};
  final files = <String, _Node>{};
}

/// The highlight.js language for a file, by its name; null when unknown.
String? languageOf(String name) {
  final lower = name.toLowerCase();
  if (lower == 'makefile' || lower == 'gnumakefile') return 'makefile';
  if (lower == 'dockerfile') return 'dockerfile';
  final dot = lower.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (lower.substring(dot + 1)) {
    'dart' => 'dart',
    'ts' || 'tsx' || 'mts' || 'cts' => 'typescript',
    'js' || 'jsx' || 'mjs' || 'cjs' => 'javascript',
    'py' => 'python',
    'sh' || 'zsh' || 'bash' => 'bash',
    'json' || 'jsonc' || 'arb' => 'json',
    'yaml' || 'yml' => 'yaml',
    'xml' || 'html' || 'htm' || 'plist' || 'svg' || 'xib' || 'storyboard' => 'xml',
    'css' => 'css',
    'scss' => 'scss',
    'sql' => 'sql',
    'go' => 'go',
    'swift' => 'swift',
    'kt' || 'kts' => 'kotlin',
    'java' || 'gradle' => 'java',
    'rs' => 'rust',
    'php' => 'php',
    'rb' => 'ruby',
    'md' || 'markdown' => 'markdown',
    'c' || 'h' => 'c',
    'cc' || 'cpp' || 'hpp' || 'm' || 'mm' => 'cpp',
    'toml' || 'ini' || 'cfg' => 'ini',
    _ => null,
  };
}
