import 'dart:io';
import 'dart:math';

import '../../utils/platform.dart';

/// A session's own working copy of a git repository: its own branch, in its
/// own folder (a git worktree), so several sessions can work in one
/// repository at once without changing each other's files. Copies live in
/// `~/.helmy/worktrees/<repository>/`, outside the repository itself.
class Worktrees {
  Worktrees({String? root}) : _root = root ?? '$homeDir/.helmy/worktrees';
  final String _root;

  Future<ProcessResult> _git(String dir, List<String> args) =>
      Process.run('git', ['-C', dir, ...args]);

  /// The top folder of the repository [folder] is in; null when it is in
  /// none (or git is not installed).
  Future<String?> repoOf(String folder) async {
    try {
      final r = await _git(folder, ['rev-parse', '--show-toplevel']);
      return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
    } on Object {
      return null;
    }
  }

  /// A branch name from what the session is about: `helmy/fix-the-login-3f9a`.
  static String branchFor(String about) {
    final words = about
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(5)
        .join('-');
    final tag = Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    return 'helmy/${words.isEmpty ? 'session' : words}-$tag';
  }

  /// A new working copy of [repo] on a new branch from where [repo] is now,
  /// named from [about]. Null, with git's words, when git would not.
  Future<({String? path, String? branch, String? error})> create(String repo, String about) async {
    final branch = branchFor(about);
    final name = repo.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).last;
    final path = '$_root/$name/${branch.substring('helmy/'.length)}';
    await Directory('$_root/$name').create(recursive: true);
    final r = await _git(repo, ['worktree', 'add', '-b', branch, path, 'HEAD']);
    if (r.exitCode != 0) return (path: null, branch: null, error: '${r.stderr}'.trim());
    return (path: path, branch: branch, error: null);
  }

  /// How many files in [path] are changed and not committed; null when it
  /// cannot be told.
  Future<int?> uncommitted(String path) async {
    final r = await _git(path, ['status', '--porcelain']);
    if (r.exitCode != 0) return null;
    return '${r.stdout}'.split('\n').where((l) => l.trim().isNotEmpty).length;
  }

  /// Removes the working copy at [path], keeping its branch (its commits stay
  /// in [repo]). Refused while it has uncommitted changes, which are the
  /// user's work: false then.
  Future<bool> remove(String repo, String path) async {
    if ((await uncommitted(path) ?? 1) > 0) return false;
    final r = await _git(repo, ['worktree', 'remove', path]);
    return r.exitCode == 0;
  }
}
