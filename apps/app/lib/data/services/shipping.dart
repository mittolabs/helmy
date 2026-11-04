import 'dart:convert';
import 'dart:io';

import 'cli_locator.dart';

/// One CI check on a pull request, and where it stands.
typedef Check = ({String name, CheckState state});

enum CheckState { pending, passed, failed, skipped }

/// A pull request, as GitHub says.
typedef PullRequest = ({int number, String url, String title, String state, List<Check> checks});

/// Where a session's branch stands on its way to merged: what is not yet
/// committed, not yet pushed, and its pull request with its checks.
class BranchState {
  BranchState({
    required this.branch,
    required this.uncommitted,
    required this.unpushed,
    required this.pushed,
    required this.head,
    this.pr,
  });

  final String branch;

  /// Changed files not committed.
  final int uncommitted;

  /// Commits not on the remote yet (all of them, when it was never pushed).
  final int unpushed;

  /// Whether the branch is on the remote at all.
  final bool pushed;

  /// The commit the branch is at.
  final String head;
  final PullRequest? pr;

  /// The checks, once all have finished: failed ones first.
  bool get checksDone => pr != null && pr!.checks.every((c) => c.state != .pending);
  List<Check> get failed => [...?pr?.checks.where((c) => c.state == .failed)];
}

/// From a session's work to a merged pull request, through git and GitHub's
/// own command (`gh`).
class Shipping {
  Shipping(this._locator);
  final CliLocator _locator;

  Future<ProcessResult?> _run(String cmd, List<String> args, String cwd) async {
    try {
      final bin = await _locator.find(cmd);
      if (bin == null) return null;
      return await Process.run(
        bin,
        args,
        workingDirectory: cwd,
        environment: await _locator.environment(),
      );
    } on Object {
      return null;
    }
  }

  Future<String?> _out(String cmd, List<String> args, String cwd) async {
    final r = await _run(cmd, args, cwd);
    return r != null && r.exitCode == 0 ? '${r.stdout}'.trim() : null;
  }

  /// Whether GitHub's command is installed and signed in, so pull requests and
  /// checks can be followed.
  Future<bool> githubReady(String cwd) async =>
      (await _run('gh', ['auth', 'status'], cwd))?.exitCode == 0;

  /// Where the branch in [cwd] stands; null when [cwd] is not in a repository.
  Future<BranchState?> state(String cwd) async {
    final branch = await _out('git', ['rev-parse', '--abbrev-ref', 'HEAD'], cwd);
    if (branch == null) return null;
    final head = await _out('git', ['rev-parse', 'HEAD'], cwd) ?? '';
    final status = await _out('git', ['status', '--porcelain'], cwd) ?? '';
    final upstream = await _out('git', ['rev-parse', '--abbrev-ref', '@{upstream}'], cwd);
    final ahead = upstream == null
        ? await _out('git', ['rev-list', '--count', 'HEAD', '--not', '--remotes'], cwd)
        : await _out('git', ['rev-list', '--count', '@{upstream}..HEAD'], cwd);
    return BranchState(
      branch: branch,
      head: head,
      uncommitted: status.split('\n').where((l) => l.trim().isNotEmpty).length,
      unpushed: int.tryParse(ahead ?? '') ?? 0,
      pushed: upstream != null,
      pr: upstream == null ? null : await pullRequest(cwd),
    );
  }

  /// The open pull request for the branch in [cwd], with its checks.
  Future<PullRequest?> pullRequest(String cwd) async {
    final out = await _out('gh', [
      'pr', 'view', '--json', 'number,url,title,state,statusCheckRollup', //
    ], cwd);
    if (out == null) return null;
    final j = jsonDecode(out) as Map;
    return (
      number: (j['number'] as num).toInt(),
      url: '${j['url']}',
      title: '${j['title']}',
      state: '${j['state']}',
      checks: [
        for (final c in (j['statusCheckRollup'] as List? ?? const []).whereType<Map>())
          (name: '${c['name'] ?? c['context'] ?? 'check'}', state: checkState(c)),
      ],
    );
  }

  /// What one entry of GitHub's check rollup says: a check run (status and
  /// conclusion) or a commit status (state).
  static CheckState checkState(Map c) {
    final conclusion = '${c['conclusion'] ?? ''}'.toUpperCase();
    final status = '${c['status'] ?? ''}'.toUpperCase();
    final state = '${c['state'] ?? ''}'.toUpperCase();
    if (state.isNotEmpty) {
      return switch (state) {
        'SUCCESS' => .passed,
        'FAILURE' || 'ERROR' => .failed,
        _ => .pending,
      };
    }
    if (status != 'COMPLETED') return .pending;
    return switch (conclusion) {
      'SUCCESS' || 'NEUTRAL' => .passed,
      'SKIPPED' => .skipped,
      _ => .failed,
    };
  }

  /// The end of what the latest failed run on [branch] printed, for the agent
  /// to fix it from; null when there is none to read.
  Future<String?> failureLog(String cwd, String branch, {int lines = 120}) async {
    final runs = await _out('gh', [
      'run', 'list', '--branch', branch, '--limit', '10', '--json', 'databaseId,conclusion', //
    ], cwd);
    if (runs == null) return null;
    final failed = (jsonDecode(runs) as List).whereType<Map>().where(
      (r) => r['conclusion'] == 'failure',
    );
    if (failed.isEmpty) return null;
    final log = await _out('gh', [
      'run',
      'view',
      '${failed.first['databaseId']}',
      '--log-failed',
    ], cwd);
    if (log == null) return null;
    final all = log.split('\n');
    return all.skip(all.length > lines ? all.length - lines : 0).join('\n');
  }
}
