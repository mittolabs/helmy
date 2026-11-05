import 'dart:io';
import 'dart:math';

import '../../utils/platform.dart';

/// A session's own working copy of a git repository: its own branch, in its
/// own folder (a git worktree), so several sessions can work in one
/// repository at once without changing each other's files. Copies live in
/// `~/.helmy/worktrees/<repository>/`, outside the repository itself.
class Worktrees {
  Worktrees({String? root, CopyRules Function()? rules})
    : _fixedRoot = root,
      _rules = rules ?? (() => const CopyRules());

  final String? _fixedRoot;
  final CopyRules Function() _rules;

  /// Where copies go: as given, else as set, else ~/.helmy/worktrees.
  String get _root => _fixedRoot ?? _rules().folder ?? '$homeDir/.helmy/worktrees';

  Future<ProcessResult> _git(String dir, List<String> args, {Duration? timeout}) {
    final run = Process.run(
      'git',
      [
        '-C', dir, ...args, //
      ],
      environment: const {'GIT_TERMINAL_PROMPT': '0'},
    );
    return timeout == null
        ? run
        : run.timeout(timeout, onTimeout: () => ProcessResult(0, 124, '', 'timed out'));
  }

  /// Where copies live: one folder per repository.
  String get root => _root;

  Future<String?> _out(String dir, List<String> args) async {
    try {
      final r = await _git(dir, args);
      return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
    } on Object {
      return null;
    }
  }

  /// The branch [repo]'s checkout is on; null when detached or not a repo.
  Future<String?> currentBranch(String repo) async {
    final b = await _out(repo, ['rev-parse', '--abbrev-ref', 'HEAD']);
    return b == null || b == 'HEAD' ? null : b;
  }

  /// [repo]'s default branch: the remote's HEAD, else main or master.
  Future<String?> defaultBranch(String repo) async {
    final remote = await _out(repo, ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD']);
    if (remote != null && remote.startsWith('origin/')) return remote.substring('origin/'.length);
    for (final b in ['main', 'master']) {
      if (await _out(repo, ['rev-parse', '--verify', '--quiet', 'refs/heads/$b']) != null) return b;
    }
    return null;
  }

  /// How far [a] is ahead of [b] in commits; null when it cannot be told.
  Future<int?> _ahead(String repo, String a, String b) async =>
      int.tryParse(await _out(repo, ['rev-list', '--count', '$b..$a']) ?? '');

  /// Where a new copy starts: the checkout's upstream, fetched, when the
  /// checkout has no commits of its own (so it starts from the newest); else
  /// the checkout itself, whose unpushed work the session may need.
  Future<String> startPoint(String repo) async {
    final upstream = await _out(repo, ['rev-parse', '--abbrev-ref', '@{upstream}']);
    if (upstream == null || !upstream.contains('/')) return 'HEAD';
    final remote = upstream.split('/').first;
    final branch = upstream.substring(remote.length + 1);
    await _git(repo, ['fetch', '--quiet', remote, branch], timeout: const Duration(seconds: 15));
    final ahead = await _ahead(repo, 'HEAD', upstream);
    return ahead == 0 ? upstream : 'HEAD';
  }

  /// The remote's default branch, fetched: where a copy starts when set to
  /// start from the remote. Null when there is no remote.
  Future<String?> remoteStart(String repo) async {
    final def = await defaultBranch(repo);
    final remote = (await _out(repo, ['remote']))?.split('\n').firstOrNull;
    if (def == null || remote == null || remote.isEmpty) return null;
    final r = await _git(repo, [
      'fetch',
      '--quiet',
      remote,
      def,
    ], timeout: const Duration(seconds: 15));
    return r.exitCode == 0 ? '$remote/$def' : null;
  }

  /// Brings [repo]'s default branch up to its remote, fast-forward only, and
  /// only when it can do no harm: the checkout is on the default branch, has
  /// no uncommitted changes and no commits of its own. True when it moved.
  Future<bool> pullIfClean(String repo) async {
    final def = await defaultBranch(repo);
    if (def == null || await currentBranch(repo) != def) return false;
    if ((await uncommitted(repo) ?? 1) > 0) return false;
    final fetched = await _git(repo, [
      'fetch',
      '--quiet',
      'origin',
      def,
    ], timeout: const Duration(seconds: 20));
    if (fetched.exitCode != 0) return false;
    if ((await _ahead(repo, 'HEAD', 'origin/$def') ?? 1) > 0) return false;
    if ((await _ahead(repo, 'origin/$def', 'HEAD') ?? 0) == 0) return false;
    final r = await _git(repo, ['merge', '--ff-only', '--quiet', 'origin/$def']);
    return r.exitCode == 0;
  }

  /// Whether [branch] has been merged into [repo]'s default branch: by git
  /// (a merge or fast-forward), or by its pull request on GitHub (which
  /// catches a squash merge).
  Future<bool> merged(String repo, String branch) async {
    final def = await defaultBranch(repo);
    if (def == null || def == branch) return false;
    // Only a branch that has commits since it was made: a new one sits on
    // the default branch's commit, which git would call merged.
    final tip = await _out(repo, ['rev-parse', branch]);
    final born = (await _out(repo, ['log', '-g', '--format=%H', branch]))?.split('\n').last;
    if (tip != null && born != null && tip != born) {
      for (final base in [def, 'origin/$def']) {
        final r = await _git(repo, ['merge-base', '--is-ancestor', branch, base]);
        if (r.exitCode == 0) return true;
      }
    }
    try {
      final r = await Process.run('gh', [
        'pr', 'list', '--head', branch, '--state', 'merged', '--json', 'number', '--limit', '1', //
      ], workingDirectory: repo).timeout(const Duration(seconds: 15));
      return r.exitCode == 0 && '${r.stdout}'.trim().startsWith('[{');
    } on Object {
      return false;
    }
  }

  /// Puts back the working copy at [path] on [branch], after it was tidied
  /// away. True when it is there.
  Future<bool> restore(String repo, String path, String branch) async {
    if (Directory(path).existsSync()) return true;
    await _git(repo, ['worktree', 'prune']);
    final r = await _git(repo, ['worktree', 'add', path, branch]);
    return r.exitCode == 0;
  }

  /// The working copies of [repo] under Helmy's folder, by their real
  /// paths (see [canonical]).
  Future<List<String>> copiesOf(String repo) async {
    final list = await _out(repo, ['worktree', 'list', '--porcelain']) ?? '';
    final under = '${canonical(_root)}/';
    return [
      for (final line in list.split('\n'))
        if (line.startsWith('worktree ') && canonical(line.substring(9)).startsWith(under))
          canonical(line.substring(9)),
    ];
  }

  /// [path] with its symbolic links followed: git says /private/var where
  /// a path was given as /var, the same folder.
  static String canonical(String path) {
    try {
      return Directory(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return path;
    }
  }

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

  /// A branch name from what the session is about: `helmy/fix-the-login-3f9a`
  /// with a [prefix], or by kind of change (`fix/the-login-3f9a`,
  /// `feat/...`) when [semantic].
  static String branchFor(String about, {String prefix = 'helmy/', bool semantic = false}) {
    final words = about
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(5)
        .join('-');
    final tag = Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    final p = semantic ? '${kindOf(about)}/' : prefix;
    return '$p${words.isEmpty ? 'session' : words}-$tag';
  }

  /// The kind of change [about] asks for, as Conventional Commits names it.
  static String kindOf(String about) {
    final a = about.toLowerCase();
    if (RegExp(r'\b(fix|bug|broken|crash|error|wrong|fails?|failing)\b').hasMatch(a)) return 'fix';
    if (RegExp(r'\b(docs?|readme|document)\b').hasMatch(a)) return 'docs';
    if (RegExp(r'\b(refactor|clean ?up|tidy|rename)\b').hasMatch(a)) return 'refactor';
    if (RegExp(r'\b(tests?)\b').hasMatch(a)) return 'test';
    return 'feat';
  }

  /// A new working copy of [repo] on a new branch from where [repo] is now,
  /// named from [about]. Null, with git's words, when git would not.
  Future<({String? path, String? branch, String? error})> create(String repo, String about) async {
    final rules = _rules();
    final branch = branchFor(about, prefix: rules.prefix, semantic: rules.semantic);
    final name = repo.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).last;
    final path = '$_root/$name/${branch.split('/').last}';
    await Directory('$_root/$name').create(recursive: true);
    final from = rules.fromRemote ? await remoteStart(repo) : null;
    final r = await _git(repo, [
      'worktree',
      'add',
      '-b',
      branch,
      path,
      from ?? await startPoint(repo),
    ]);
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

/// How threads' own copies are made, from Settings.
class CopyRules {
  const CopyRules({
    this.prefix = 'helmy/',
    this.semantic = false,
    this.fromRemote = false,
    this.folder,
  });

  /// Before each branch's name, unless [semantic].
  final String prefix;

  /// Branches named by kind of change: fix/, feat/, docs/.
  final bool semantic;

  /// Start from the remote's default branch, not the checkout.
  final bool fromRemote;

  /// Where copies go; null for ~/.helmy/worktrees.
  final String? folder;
}
