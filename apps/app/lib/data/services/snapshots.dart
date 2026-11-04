import 'dart:io';

import '../../domain/models/snapshot.dart';

export '../../domain/models/snapshot.dart';

/// Snapshots, changes since one, and putting files back as they were. Every
/// method needs the folder to be a git repository and does nothing otherwise:
/// callers fall back to what the agents report.
class Snapshots {
  /// git's empty tree, the "before" of a repository with no commit yet.
  static const _emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';

  Future<ProcessResult> _git(String cwd, List<String> args) =>
      Process.run('git', args, workingDirectory: cwd).timeout(const Duration(seconds: 20));

  Future<bool> isRepo(String cwd) async {
    try {
      final r = await _git(cwd, ['rev-parse', '--is-inside-work-tree']);
      return r.exitCode == 0 && '${r.stdout}'.trim() == 'true';
    } on Object {
      return false;
    }
  }

  /// The folder as it is now, or null when it is not a git repository.
  Future<Snapshot?> take(String cwd) async {
    if (!await isRepo(cwd)) return null;
    final stash = await _git(cwd, ['stash', 'create']);
    var sha = '${stash.stdout}'.trim();
    // A clean tree makes no stash commit: the snapshot is the last commit,
    // or git's empty tree in a repository with none yet.
    if (sha.isEmpty) {
      final head = await _git(cwd, ['rev-parse', 'HEAD']);
      sha = head.exitCode == 0 ? '${head.stdout}'.trim() : _emptyTree;
    }
    // Untracked files: their contents kept as objects, small ones only.
    final kept = <String, String>{};
    for (final path in (await _untracked(cwd)).take(2000)) {
      final f = File('$cwd/$path');
      if (!f.existsSync() || f.lengthSync() > 5 * 1024 * 1024) continue;
      final r = await _git(cwd, ['hash-object', '-w', '--', path]);
      if (r.exitCode == 0) kept[path] = '${r.stdout}'.trim();
    }
    return Snapshot(sha: sha, untracked: kept);
  }

  Future<List<String>> _untracked(String cwd) async {
    final r = await _git(cwd, ['ls-files', '--others', '--exclude-standard']);
    return '${r.stdout}'.split('\n').where((l) => l.isNotEmpty).toList();
  }

  /// Every file changed since [since]: edited, added or removed, whatever did it.
  Future<List<FileChange>> changes(String cwd, Snapshot since) async {
    final out = <FileChange>[];
    final stat = await _git(cwd, ['diff', '--numstat', '--no-renames', since.sha]);
    final status = await _git(cwd, ['diff', '--name-status', '--no-renames', since.sha]);
    final kinds = {
      for (final l in '${status.stdout}'.split('\n').where((l) => l.contains('\t')))
        l.split('\t').last: switch (l[0]) {
          'A' => 'added',
          'D' => 'removed',
          _ => 'edited',
        },
    };
    for (final l in '${stat.stdout}'.split('\n').where((l) => l.isNotEmpty)) {
      final p = l.split('\t');
      if (p.length < 3) continue;
      out.add((
        path: p[2],
        added: int.tryParse(p[0]) ?? 0,
        removed: int.tryParse(p[1]) ?? 0,
        kind: kinds[p[2]] ?? 'edited',
      ));
    }
    // New files git does not track, that were not there at the snapshot.
    final before = since.untracked.keys.toSet();
    for (final path in await _untracked(cwd)) {
      if (before.contains(path)) continue;
      final lines = await _lineCount('$cwd/$path');
      out.add((path: path, added: lines, removed: 0, kind: 'added'));
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// What changed from [from] to [to]: one turn's own work, when they are
  /// the checkpoints before its message and before the next.
  Future<List<FileChange>> changesBetween(String cwd, Snapshot from, Snapshot to) async {
    final out = <FileChange>[];
    final stat = await _git(cwd, ['diff', '--numstat', '--no-renames', from.sha, to.sha]);
    final status = await _git(cwd, ['diff', '--name-status', '--no-renames', from.sha, to.sha]);
    final kinds = {
      for (final l in '${status.stdout}'.split('\n').where((l) => l.contains('\t')))
        l.split('\t').last: switch (l[0]) {
          'A' => 'added',
          'D' => 'removed',
          _ => 'edited',
        },
    };
    final seen = <String>{};
    for (final l in '${stat.stdout}'.split('\n').where((l) => l.isNotEmpty)) {
      final p = l.split('\t');
      if (p.length < 3) continue;
      seen.add(p[2]);
      out.add((
        path: p[2],
        added: int.tryParse(p[0]) ?? 0,
        removed: int.tryParse(p[1]) ?? 0,
        kind: kinds[p[2]] ?? 'edited',
      ));
    }
    // Untracked files, compared by the objects kept for them.
    for (final path in {...from.untracked.keys, ...to.untracked.keys}) {
      if (seen.contains(path)) continue;
      final a = from.untracked[path], b = to.untracked[path];
      if (a == b) continue;
      if (a != null && b != null) {
        final n = await _git(cwd, ['diff', '--numstat', a, b]);
        final p = '${n.stdout}'.trim().split('\t');
        out.add((
          path: path,
          added: p.length > 1 ? int.tryParse(p[0]) ?? 0 : 0,
          removed: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
          kind: 'edited',
        ));
      } else if (b != null) {
        out.add((path: path, added: (await _blobLines(cwd, b)).length, removed: 0, kind: 'added'));
      } else if (a != null &&
          (await _git(cwd, ['cat-file', '-e', '${to.sha}:$path'])).exitCode != 0) {
        out.add((
          path: path,
          added: 0,
          removed: (await _blobLines(cwd, a)).length,
          kind: 'removed',
        ));
      }
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// One file's unified diff from [from] to [to].
  Future<String> diffBetween(String cwd, Snapshot from, Snapshot to, String path) async {
    final tracked = await _git(cwd, ['diff', '--no-renames', from.sha, to.sha, '--', path]);
    final text = '${tracked.stdout}';
    if (text.trim().isNotEmpty) return text;
    final a = from.untracked[path], b = to.untracked[path];
    if (a != null && b != null) return '${(await _git(cwd, ['diff', a, b])).stdout}';
    if (b != null) return _wholeFile(path, await _blobLines(cwd, b), '+');
    if (a != null) return _wholeFile(path, await _blobLines(cwd, a), '-');
    return '';
  }

  Future<List<String>> _blobLines(String cwd, String blob) async {
    final r = await _git(cwd, ['cat-file', '-p', blob]);
    final text = '${r.stdout}';
    if (text.isEmpty) return const [];
    return text.endsWith('\n') ? text.substring(0, text.length - 1).split('\n') : text.split('\n');
  }

  /// A file added or removed whole, as a unified diff.
  static String _wholeFile(String path, List<String> lines, String sign) {
    final range = sign == '+' ? '-0,0 +1,${lines.length}' : '-1,${lines.length} +0,0';
    return '--- ${sign == '+' ? '/dev/null' : 'a/$path'}\n'
        '+++ ${sign == '+' ? 'b/$path' : '/dev/null'}\n'
        '@@ $range @@\n'
        '${[for (final l in lines) '$sign$l'].join('\n')}\n';
  }

  Future<int> _lineCount(String path) async {
    try {
      return (await File(path).readAsString()).split('\n').length;
    } on Object {
      return 0;
    }
  }

  /// One file's unified diff since [since].
  Future<String> diff(String cwd, Snapshot since, String path) async {
    final tracked = await _git(cwd, ['diff', '--no-renames', since.sha, '--', path]);
    final text = '${tracked.stdout}';
    if (text.trim().isNotEmpty) return text;
    // A new untracked file: all of it is added.
    final added = await _git(cwd, ['diff', '--no-index', '--', '/dev/null', path]);
    return '${added.stdout}';
  }

  /// Puts [paths] back as they were at [since]: edited and removed files get
  /// their old contents, files that did not exist then are removed. The index,
  /// branches and history are not touched.
  Future<void> restore(String cwd, Snapshot since, List<String> paths) async {
    for (final path in paths) {
      final existed = await _git(cwd, ['cat-file', '-e', '${since.sha}:$path']);
      if (existed.exitCode == 0) {
        await _git(cwd, ['restore', '--source=${since.sha}', '--worktree', '--', path]);
      } else if (since.untracked[path] case final blob?) {
        // An untracked file of yours: back from the object kept for it.
        final r = await Process.run(
          'git',
          ['cat-file', 'blob', blob],
          workingDirectory: cwd,
          stdoutEncoding: null,
        );
        if (r.exitCode == 0) {
          final f = File('$cwd/$path');
          await f.parent.create(recursive: true);
          await f.writeAsBytes(r.stdout as List<int>);
        }
      } else {
        final f = File('$cwd/$path');
        if (await f.exists()) await f.delete();
      }
    }
  }
}
