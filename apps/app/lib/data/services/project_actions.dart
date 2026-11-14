import 'dart:convert';
import 'dart:io';

import '../../domain/models/project_action.dart';

/// The actions a project already says it is worked with, read from its own
/// files at [folder]: package.json scripts (run as its lockfile says: npm,
/// pnpm, yarn or bun), Makefile and justfile targets, deno.json tasks, and
/// the usual commands of a Flutter, Dart, Rust or Go project or a Compose
/// file. Grouped by the file, in the order the files are listed here.
List<ProjectAction> findActions(String folder) => [
  ..._package(folder),
  ..._make(folder),
  ..._just(folder),
  ..._deno(folder),
  ..._dart(folder),
  ..._cargo(folder),
  ..._go(folder),
  ..._compose(folder),
];

String? _read(String path) {
  try {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync() : null;
  } on Object {
    return null;
  }
}

/// Whether [path] is there; not, where it cannot be looked for (in a browser,
/// the folder is on the computer Helmy runs on).
bool _has(String path) {
  try {
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  } on Object {
    return false;
  }
}

/// The scripts people run most, first, in this order; then the rest as the
/// file lists them.
const _first = [
  'dev',
  'start',
  'run',
  'serve',
  'preview',
  'test',
  'build',
  'lint',
  'typecheck',
  'check',
];

/// Ordered with the usual names first.
List<String> _ordered(Iterable<String> names) {
  final all = names.toList();
  return [
    for (final n in _first)
      if (all.contains(n)) n,
    for (final n in all)
      if (!_first.contains(n)) n,
  ];
}

List<ProjectAction> _package(String folder) {
  final text = _read('$folder/package.json');
  if (text == null) return const [];
  Map? scripts;
  try {
    scripts = (jsonDecode(text) as Map)['scripts'] as Map?;
  } on Object {
    return const [];
  }
  if (scripts == null) return const [];
  final run = _has('$folder/pnpm-lock.yaml')
      ? 'pnpm run'
      : _has('$folder/yarn.lock')
      ? 'yarn'
      : _has('$folder/bun.lockb') || _has('$folder/bun.lock')
      ? 'bun run'
      : 'npm run';
  final names = scripts.keys.whereType<String>().toSet();
  // Hooks the package manager runs by itself (install's, and pre/post of
  // another script) are not things to run by hand.
  const lifecycle = {
    'preinstall', 'install', 'postinstall', 'prepare', 'prepublish', 'prepublishOnly', //
    'prepack', 'postpack', 'preversion', 'version', 'postversion', 'dependencies',
  };
  bool hook(String n) =>
      lifecycle.contains(n) ||
      (n.startsWith('pre') && names.contains(n.substring(3))) ||
      (n.startsWith('post') && names.contains(n.substring(4)));
  return [
    for (final n in _ordered(names.where((n) => !hook(n))))
      ProjectAction(name: n, command: '$run $n', from: 'package.json'),
  ];
}

List<ProjectAction> _make(String folder) {
  final file = [
    'GNUmakefile',
    'makefile',
    'Makefile',
  ].firstWhere((f) => _has('$folder/$f'), orElse: () => '');
  if (file.isEmpty) return const [];
  final text = _read('$folder/$file') ?? '';
  // A rule: a name at the line's start, then ":" that is not ":=" or "::=".
  final rule = RegExp(r'^([A-Za-z0-9][A-Za-z0-9_\-./]*)\s*:(?![:=])');
  final names = <String>[];
  for (final line in const LineSplitter().convert(text)) {
    final m = rule.firstMatch(line);
    final name = m?[1];
    if (name == null || name.contains('/') || name.contains('.') || names.contains(name)) continue;
    names.add(name);
  }
  return [
    for (final n in _ordered(names)) ProjectAction(name: n, command: 'make $n', from: 'Makefile'),
  ];
}

List<ProjectAction> _just(String folder) {
  final file = [
    'justfile',
    'Justfile',
    '.justfile',
  ].firstWhere((f) => _has('$folder/$f'), orElse: () => '');
  if (file.isEmpty) return const [];
  final text = _read('$folder/$file') ?? '';
  // A recipe without parameters it must be given: "name:" or "name arg='x':".
  final recipe = RegExp(r'^@?([A-Za-z0-9][A-Za-z0-9_-]*)((?:\s+[A-Za-z_][\w-]*=\S+)*)\s*:(?!=)');
  const words = {'set', 'alias', 'export', 'import', 'mod'};
  final names = <String>[];
  for (final line in const LineSplitter().convert(text)) {
    final name = recipe.firstMatch(line)?[1];
    if (name == null || words.contains(name) || name.startsWith('_') || names.contains(name)) {
      continue;
    }
    names.add(name);
  }
  return [
    for (final n in _ordered(names)) ProjectAction(name: n, command: 'just $n', from: 'justfile'),
  ];
}

List<ProjectAction> _deno(String folder) {
  final text = _read('$folder/deno.json') ?? _read('$folder/deno.jsonc');
  if (text == null) return const [];
  Map? tasks;
  try {
    tasks = (jsonDecode(text) as Map)['tasks'] as Map?;
  } on Object {
    return const [];
  }
  return [
    for (final n in _ordered((tasks ?? const {}).keys.whereType<String>()))
      ProjectAction(name: n, command: 'deno task $n', from: 'deno.json'),
  ];
}

/// Whether [folder] or a folder above it pins Flutter with fvm.
bool _fvm(String folder) {
  var dir = Directory(folder).absolute;
  for (var i = 0; i < 6; i++) {
    if (_has('${dir.path}/.fvmrc') || _has('${dir.path}/.fvm/fvm_config.json')) return true;
    final up = dir.parent;
    if (up.path == dir.path) break;
    dir = up;
  }
  return false;
}

List<ProjectAction> _dart(String folder) {
  final text = _read('$folder/pubspec.yaml');
  if (text == null) return const [];
  final fvm = _fvm(folder) ? 'fvm ' : '';
  if (RegExp(r'sdk:\s*flutter').hasMatch(text)) {
    return [
      ProjectAction(name: 'run', command: '${fvm}flutter run', from: 'Flutter'),
      if (_has('$folder/test'))
        ProjectAction(name: 'test', command: '${fvm}flutter test', from: 'Flutter'),
      ProjectAction(name: 'analyze', command: '${fvm}flutter analyze', from: 'Flutter'),
    ];
  }
  return [
    if (_has('$folder/bin')) ProjectAction(name: 'run', command: '${fvm}dart run', from: 'Dart'),
    if (_has('$folder/test')) ProjectAction(name: 'test', command: '${fvm}dart test', from: 'Dart'),
    ProjectAction(name: 'analyze', command: '${fvm}dart analyze', from: 'Dart'),
  ];
}

List<ProjectAction> _cargo(String folder) => _has('$folder/Cargo.toml')
    ? const [
        ProjectAction(name: 'run', command: 'cargo run', from: 'Cargo'),
        ProjectAction(name: 'test', command: 'cargo test', from: 'Cargo'),
        ProjectAction(name: 'build', command: 'cargo build', from: 'Cargo'),
      ]
    : const [];

List<ProjectAction> _go(String folder) => _has('$folder/go.mod')
    ? [
        if (_has('$folder/main.go'))
          const ProjectAction(name: 'run', command: 'go run .', from: 'Go'),
        const ProjectAction(name: 'test', command: 'go test ./...', from: 'Go'),
        const ProjectAction(name: 'build', command: 'go build ./...', from: 'Go'),
      ]
    : const [];

List<ProjectAction> _compose(String folder) =>
    [
      'compose.yaml',
      'compose.yml',
      'docker-compose.yml',
      'docker-compose.yaml',
    ].any((f) => _has('$folder/$f'))
    ? const [ProjectAction(name: 'up', command: 'docker compose up', from: 'Docker Compose')]
    : const [];
