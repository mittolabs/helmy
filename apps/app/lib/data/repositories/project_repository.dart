import 'dart:io';

import '../../domain/models/engine.dart';
import '../../domain/models/session.dart';
import '../services/worktrees.dart';
import 'settings_repository.dart';

/// The projects sessions work in: which git repository a folder is in, what
/// Helmy may do there, and a session's own working copy going away with it.
abstract class ProjectRepository {
  /// The top folder of the repository [folder] is in; null when none.
  Future<String?> repoOf(String folder);

  /// The branch [folder]'s checkout is on; null outside git or detached.
  Future<String?> branchOf(String folder);

  /// The level a new chat in [folder] starts at: always the one where Helmy
  /// judges each action. A level saved before approvals were Helmy's (a
  /// project's, or the default) has no setting left to change it, so it no
  /// longer counts.
  Future<PermissionLevel> levelFor(String folder);

  /// Removes a session's own working copy at [path] of [repo], keeping its
  /// branch; refused (false) while it holds uncommitted work.
  Future<bool> removeCopy(String repo, String path);

  /// Puts back a session's working copy tidied away, on its branch.
  Future<bool> restoreCopy(Session session);

  /// Keeps working copies and checkouts in order, for [sessions]: copies of
  /// archived sessions, of merged branches, and of no session go (never one
  /// with uncommitted work; branches stay), and default branches are brought
  /// up to date where that can do no harm. Sessions in [working] are at work
  /// now: their copies count as theirs and are not touched. What was done.
  /// [settled]: sessions whose chat settled, whose copies go too.
  Future<List<String>> tidy(
    List<Session> sessions, {
    Set<String> working = const {},
    Set<String> settled = const {},
  });
}

class ProjectRepositoryGit implements ProjectRepository {
  ProjectRepositoryGit(this._settings, {Worktrees? worktrees}) : _git = worktrees ?? Worktrees();
  final SettingsRepository _settings;
  final Worktrees _git;

  @override
  Future<String?> repoOf(String folder) => _git.repoOf(folder);

  @override
  Future<String?> branchOf(String folder) => _git.currentBranch(folder);

  @override
  Future<PermissionLevel> levelFor(String folder) async => .ask;

  @override
  Future<bool> removeCopy(String repo, String path) => _git.remove(repo, path);

  @override
  Future<bool> restoreCopy(Session s) async {
    if (!s.ownCopy) return true;
    return _git.restore(s.repo!, s.cwd, s.branch!);
  }

  @override
  Future<List<String>> tidy(
    List<Session> sessions, {
    Set<String> working = const {},
    Set<String> settled = const {},
  }) async {
    final done = <String>[];
    final copies = [
      for (final s in sessions)
        if (s.ownCopy) s,
    ];
    for (final s in copies) {
      if (working.contains(s.id) || !Directory(s.cwd).existsSync()) continue;
      final why = s.archived
          ? 'archived'
          : settled.contains(s.id)
          ? 'settled'
          : await _git.merged(s.repo!, s.branch!)
          ? 'merged'
          : null;
      if (why != null && await _git.remove(s.repo!, s.cwd)) done.add('Removed ${s.cwd} ($why)');
    }
    // Copies no session has (left by a crash, or a session deleted elsewhere).
    final repos = {
      for (final s in sessions)
        if (s.repo != null) s.repo!,
    };
    final owned = {for (final s in copies) Worktrees.canonical(s.cwd)};
    for (final repo in repos) {
      for (final path in await _git.copiesOf(repo)) {
        if (!owned.contains(path) && await _git.remove(repo, path)) {
          done.add('Removed $path (no thread)');
        }
      }
    }
    // The default branch of each project worked in, kept current.
    if (_settings.settings.keepDefaultCurrent) {
      final checkouts = {
        for (final s in sessions)
          if (!s.archived) s.repo ?? await _git.repoOf(s.cwd),
      }.whereType<String>();
      for (final repo in checkouts) {
        if (await _git.pullIfClean(repo)) done.add('Brought $repo up to date');
      }
    }
    return done;
  }
}
