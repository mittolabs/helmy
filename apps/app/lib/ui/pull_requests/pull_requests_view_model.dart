import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/desktop_service.dart';
import '../../data/services/pull_requests.dart';
import '../../domain/models/session.dart';
import '../../utils/result.dart';

enum PrSort {
  updated('Recently updated'),
  newest('Newest'),
  oldest('Oldest');

  const PrSort(this.label);
  final String label;
}

/// The open pull requests of every project worked in here, in one list to
/// search, sort and act on, as T3 Code has them.
class PullRequestsViewModel extends ChangeNotifier {
  PullRequestsViewModel({
    required this._prs,
    required this._sessions,
    required this._conversations,
    required this._settings,
    this._desktop,
  });

  final PullRequests _prs;
  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final SettingsRepository _settings;
  final DesktopService? _desktop;

  /// All of them; null while looking the first time.
  List<PullRequest>? all;

  /// What kept some or all from being seen: 'missing' (GitHub's command is
  /// not installed), 'signedOut', or words to show.
  String? problem;

  /// The signed-in GitHub user.
  String? me;
  bool loading = false;

  String query = '';
  PrSort sort = .updated;

  /// Only the user's own, or everyone's.
  bool mine = false;

  /// The folders worked in: every session's project, and every project in
  /// Settings.
  List<String> get folders => {
    for (final s in _sessions.sessions) s.repo ?? s.cwd,
    ..._settings.settings.projects.keys,
  }.toList();

  Future<void> load() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    final r = await _prs.list(folders);
    all = r.prs;
    problem = r.problem;
    me = r.me;
    loading = false;
    notifyListeners();
    // Their checks after, as they come: several times slower to read.
    final byFolder = {for (final p in r.prs) p.folder};
    await Future.wait([
      for (final f in byFolder)
        () async {
          final checks = await _prs.checks(f);
          final list = all;
          if (list == null) return;
          all = [
            for (final p in list) p.folder == f ? p.withChecks(checks[p.number] ?? p.checks) : p,
          ];
          notifyListeners();
        }(),
    ]);
  }

  void search(String q) {
    query = q;
    notifyListeners();
  }

  void sortBy(PrSort s) {
    sort = s;
    notifyListeners();
  }

  void showMine(bool on) {
    mine = on;
    notifyListeners();
  }

  /// What shows: matching the search, the user's own if asked, in order.
  List<PullRequest> get shown {
    final list = [
      for (final p in all ?? const <PullRequest>[])
        if ((!mine || p.author == me) && matchesQuery(p, query)) p,
    ];
    list.sort(
      (a, b) => switch (sort) {
        .updated => b.updatedAt.compareTo(a.updatedAt),
        .newest => b.createdAt.compareTo(a.createdAt),
        .oldest => a.createdAt.compareTo(b.createdAt),
      },
    );
    return list;
  }

  /// The session whose branch the pull request is, when Helmy made it.
  Session? sessionOf(PullRequest pr) => _sessions.sessions
      .where((s) => s.branch == pr.branch && (s.repo == pr.folder || s.cwd == pr.folder))
      .firstOrNull;

  Future<void> openOnGitHub(PullRequest pr) => openUrl(pr.url);

  /// Opens [url] in the browser.
  Future<void> openUrl(String url) async => _desktop?.open(url);

  /// A session in the pull request's project, asked to review it. Its id.
  Future<String?> review(PullRequest pr) async {
    final made = await _sessions.create(cwd: pr.folder, title: 'Review #${pr.number}: ${pr.title}');
    if (made case Ok(value: final s)) {
      unawaited(
        _conversations.send(
          s,
          'Review pull request #${pr.number}, "${pr.title}" (${pr.url}). Read what it changes '
          '(gh pr view ${pr.number} and gh pr diff ${pr.number}), then tell me what is good, '
          'what is wrong or risky, and what to change before it merges. Change nothing yourself.',
        ),
      );
      return s.id;
    }
    return null;
  }

  /// A guide for the person to review [pr] by: the order to read it in,
  /// what each part does, and what to check. In a new chat; its id.
  Future<String?> guide(PullRequest pr) async {
    final made = await _sessions.create(
      cwd: pr.folder,
      title: 'Guide to #${pr.number}: ${pr.title}',
    );
    if (made case Ok(value: final s)) {
      unawaited(
        _conversations.send(
          s,
          'Write me a guide to reviewing pull request #${pr.number}, "${pr.title}" (${pr.url}), '
          'so I can review it myself. Read it first (gh pr view ${pr.number} and gh pr diff '
          '${pr.number}). Then: what it is for, in two sentences; the order to read the files '
          'in, each with what its change does in a line; what to check closely and why (the '
          'risky parts, what is not tested); and questions worth asking the author. Point at '
          'files and lines. Do not review it for me, and change nothing.',
        ),
      );
      return s.id;
    }
    return null;
  }

  Future<bool> signIn() async {
    final ok = await _prs.signIn();
    if (ok) await load();
    return ok;
  }
}
