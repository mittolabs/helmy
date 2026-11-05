import 'dart:convert';
import 'dart:io';

import 'cli_locator.dart';

/// How a pull request's checks stand, all told.
enum ChecksState { none, passing, failing, running }

/// One open pull request, as the list shows it.
class PullRequest {
  const PullRequest({
    required this.repo,
    required this.folder,
    required this.number,
    required this.title,
    required this.author,
    required this.branch,
    required this.updatedAt,
    required this.createdAt,
    required this.url,
    required this.draft,
    required this.review,
    required this.labels,
    required this.checks,
  });

  /// The repository on GitHub ("owner/name"), and a folder on this Mac in it.
  final String repo, folder;
  final int number;
  final String title, author, branch, url;
  final DateTime updatedAt, createdAt;
  final bool draft;

  /// APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED; null when none is asked.
  final String? review;
  final List<String> labels;

  /// Null until they are known: they are read after the list, being slow.
  final ChecksState? checks;

  PullRequest withChecks(ChecksState? c) => PullRequest(
    repo: repo,
    folder: folder,
    number: number,
    title: title,
    author: author,
    branch: branch,
    updatedAt: updatedAt,
    createdAt: createdAt,
    url: url,
    draft: draft,
    review: review,
    labels: labels,
    checks: c,
  );

  static PullRequest fromJson(
    Map<String, Object?> j, {
    required String repo,
    required String folder,
  }) => PullRequest(
    repo: repo,
    folder: folder,
    number: (j['number'] as num).toInt(),
    title: '${j['title'] ?? ''}',
    author: '${(j['author'] as Map?)?['login'] ?? ''}',
    branch: '${j['headRefName'] ?? ''}',
    updatedAt: DateTime.tryParse('${j['updatedAt']}') ?? DateTime(1970),
    createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime(1970),
    url: '${j['url'] ?? ''}',
    draft: j['isDraft'] == true,
    review: switch (j['reviewDecision']) {
      final String s when s.isNotEmpty => s,
      _ => null,
    },
    labels: [for (final l in (j['labels'] as List? ?? const []).whereType<Map>()) '${l['name']}'],
    checks: j.containsKey('statusCheckRollup')
        ? checksOf(j['statusCheckRollup'] as List? ?? const [])
        : null,
  );

  /// GitHub's checks and statuses, as one state: any failing, else any
  /// running, else passing; none when there are none.
  static ChecksState checksOf(List rollup) {
    if (rollup.isEmpty) return .none;
    var running = false;
    for (final c in rollup.whereType<Map>()) {
      final outcome = '${c['conclusion'] ?? c['state'] ?? ''}'.toUpperCase();
      final status = '${c['status'] ?? ''}'.toUpperCase();
      if (const {
        'FAILURE',
        'ERROR',
        'CANCELLED',
        'TIMED_OUT',
        'ACTION_REQUIRED',
      }.contains(outcome)) {
        return .failing;
      }
      if (status == 'IN_PROGRESS' ||
          status == 'QUEUED' ||
          status == 'PENDING' ||
          outcome == 'PENDING' ||
          (outcome.isEmpty && status != 'COMPLETED')) {
        running = true;
      }
    }
    return running ? .running : .passing;
  }
}

/// What came back from looking: the pull requests, and anything that kept
/// some from being seen, said plainly.
typedef PullRequestList = ({List<PullRequest> prs, String? problem, String? me});

/// Open pull requests across every project, through GitHub's own command.
class PullRequests {
  PullRequests(this._locator);
  final CliLocator _locator;

  Future<ProcessResult?> _gh(List<String> args, String cwd) async {
    final bin = await _locator.find('gh');
    if (bin == null) return null;
    try {
      return await Process.run(
        bin,
        args,
        workingDirectory: cwd,
        environment: {...await _locator.environment(), 'GH_PROMPT_DISABLED': '1'},
      ).timeout(const Duration(seconds: 30));
    } on Object {
      return null;
    }
  }

  /// Whether any of [folders] is in a repository on GitHub: where pull
  /// requests mean something. Read from git's own remotes, asking GitHub
  /// nothing.
  Future<bool> anyOnGitHub(Iterable<String> folders) async {
    final git = await _locator.find('git');
    if (git == null) return false;
    for (final f in folders.toSet()) {
      if (!Directory(f).existsSync()) continue;
      try {
        final r = await Process.run(git, [
          'remote',
          '-v',
        ], workingDirectory: f).timeout(const Duration(seconds: 5));
        if (r.exitCode == 0 && '${r.stdout}'.contains('github.com')) return true;
      } on Object {
        // Not a repository, or git did not answer: not this one.
      }
    }
    return false;
  }

  /// Open pull requests in the repositories [folders] are in, newest first.
  Future<PullRequestList> list(Iterable<String> folders) async {
    if (await _locator.find('gh') == null) {
      return (prs: const <PullRequest>[], problem: 'missing', me: null);
    }
    final home = folders.firstOrNull ?? Directory.current.path;
    final auth = await _gh(['auth', 'status'], home);
    if (auth == null || auth.exitCode != 0) {
      return (prs: const <PullRequest>[], problem: 'signedOut', me: null);
    }
    final me = '${(await _gh(['api', 'user', '-q', '.login'], home))?.stdout ?? ''}'.trim();
    // One folder per repository: a project's copies are the same repository.
    final repos = <String, String>{};
    await Future.wait([
      for (final f in folders.toSet())
        if (Directory(f).existsSync())
          () async {
            final r = await _gh([
              'repo',
              'view',
              '--json',
              'nameWithOwner',
              '-q',
              '.nameWithOwner',
            ], f);
            final name = '${r?.stdout ?? ''}'.trim();
            if (r?.exitCode == 0 && name.isNotEmpty) repos.putIfAbsent(name, () => f);
          }(),
    ]);
    final prs = <PullRequest>[];
    var failed = 0;
    await Future.wait([
      for (final MapEntry(key: repo, value: folder) in repos.entries)
        () async {
          final r = await _gh([
            'pr', 'list', '--state', 'open', '--limit', '100', '--json', //
            'number,title,author,headRefName,updatedAt,createdAt,url,isDraft,reviewDecision,labels',
          ], folder);
          if (r == null || r.exitCode != 0) {
            failed++;
            return;
          }
          for (final j in (jsonDecode('${r.stdout}') as List).whereType<Map>()) {
            prs.add(PullRequest.fromJson(j.cast<String, Object?>(), repo: repo, folder: folder));
          }
        }(),
    ]);
    prs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return (
      prs: prs,
      problem: failed == 0
          ? null
          : 'Some repositories did not answer ($failed of ${repos.length}).',
      me: me.isEmpty ? null : me,
    );
  }

  /// The checks of each open pull request in the repository at [folder], by
  /// number: read apart from the list, as they take several times as long.
  Future<Map<int, ChecksState>> checks(String folder) async {
    final r = await _gh([
      'pr', 'list', '--state', 'open', '--limit', '100', '--json', 'number,statusCheckRollup', //
    ], folder);
    if (r == null || r.exitCode != 0) return const {};
    return {
      for (final j in (jsonDecode('${r.stdout}') as List).whereType<Map>())
        (j['number'] as num).toInt(): PullRequest.checksOf(
          j['statusCheckRollup'] as List? ?? const [],
        ),
    };
  }

  /// Signs GitHub's command in, through the browser. True when it worked.
  Future<bool> signIn() async {
    final r = await _gh([
      'auth',
      'login',
      '--web',
      '--hostname',
      'github.com',
      '--git-protocol',
      'https',
    ], Directory.current.path);
    return r?.exitCode == 0;
  }
}

/// Whether [pr] matches what was typed: words in its title, branch or
/// number, and `label:`, `author:`, `repo:` and `is:draft` (`-` before any
/// to leave those out).
bool matchesQuery(PullRequest pr, String query) {
  for (final raw in query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
    final not = raw.startsWith('-') && raw.length > 1;
    final w = not ? raw.substring(1) : raw;
    final hit = switch (w) {
      final x when x.startsWith('label:') => pr.labels.any(
        (l) => l.toLowerCase() == x.substring(6),
      ),
      final x when x.startsWith('author:') => pr.author.toLowerCase() == x.substring(7),
      final x when x.startsWith('repo:') => pr.repo.toLowerCase().contains(x.substring(5)),
      'is:draft' => pr.draft,
      final x when x.startsWith('#') => '${pr.number}' == x.substring(1),
      final x =>
        pr.title.toLowerCase().contains(x) ||
            pr.branch.toLowerCase().contains(x) ||
            '${pr.number}' == x,
    };
    if (hit == not) return false;
  }
  return true;
}
