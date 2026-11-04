import '../../domain/models/engine.dart';
import '../services/worktrees.dart';
import 'settings_repository.dart';

/// The projects sessions work in: which git repository a folder is in, what
/// Helmy may do there, and a session's own working copy going away with it.
abstract class ProjectRepository {
  /// The top folder of the repository [folder] is in; null when none.
  Future<String?> repoOf(String folder);

  /// What Helmy may do without asking in a new session in [folder]: its
  /// project's level, or the one for everywhere.
  Future<PermissionLevel> levelFor(String folder);

  /// Removes a session's own working copy at [path] of [repo], keeping its
  /// branch; refused (false) while it holds uncommitted work.
  Future<bool> removeCopy(String repo, String path);
}

class ProjectRepositoryGit implements ProjectRepository {
  ProjectRepositoryGit(this._settings, {Worktrees? worktrees}) : _git = worktrees ?? Worktrees();
  final SettingsRepository _settings;
  final Worktrees _git;

  @override
  Future<String?> repoOf(String folder) => _git.repoOf(folder);

  @override
  Future<PermissionLevel> levelFor(String folder) async {
    final s = _settings.settings;
    final repo = await _git.repoOf(folder);
    return (repo == null ? null : s.project(repo).level) ?? s.defaultLevel;
  }

  @override
  Future<bool> removeCopy(String repo, String path) => _git.remove(repo, path);
}
