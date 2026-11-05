import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/session.dart';
import '../services/notify_service.dart';
import '../services/shipping.dart';
import 'conversation_repository.dart';
import 'session_repository.dart';

/// A session's way from work to a merged pull request: where its branch
/// stands, and asking its agent to commit and to open the pull request. With
/// the checks watched, a failure goes to the agent with what failed, to fix;
/// a pass goes to the user. Each commit's outcome is told once.
/// A session's way from work to a merged pull request.
abstract class ShipRepository extends ChangeNotifier {
  BranchState? stateOf(String sessionId);
  Future<BranchState?> refresh(Session session);
  Future<void> commit(Session session);
  Future<void> openPullRequest(Session session);
  Future<void> watch(Session session, bool on);
  Future<void> check(Session session);

  /// Threads whose pull request was seen open and then merged.
  Stream<String> get merged;
}

class ShipRepositoryGit extends ShipRepository {
  ShipRepositoryGit({
    required this._shipping,
    required this._sessions,
    required this._conversations,
    required this._notify,
    this.every = const Duration(seconds: 60),
  }) {
    _sessions.addListener(_plan);
    _plan();
  }

  final Shipping _shipping;
  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final NotifyService _notify;

  /// How often watched checks are asked about.
  final Duration every;

  final Map<String, BranchState?> _states = {};
  final _merged = StreamController<String>.broadcast();

  @override
  Stream<String> get merged => _merged.stream;

  /// Ticks of the timer, so open pull requests nobody watches are looked at
  /// less often than watched checks.
  int _ticks = 0;
  final Map<String, String> _told = {};
  Timer? _timer;

  /// What [sessionId]'s branch was last seen as; null before it was asked.
  @override
  BranchState? stateOf(String sessionId) => _states[sessionId];

  /// Asks again where [session]'s branch stands.
  @override
  Future<BranchState?> refresh(Session session) async {
    final s = await _shipping.state(session.cwd);
    final was = _states[session.id]?.pr?.state;
    _states[session.id] = s;
    if (was == 'OPEN' && s?.pr?.state == 'MERGED') _merged.add(session.id);
    notifyListeners();
    _plan();
    return s;
  }

  /// Asks the agent to commit the work, in the repository's own style.
  @override
  Future<void> commit(Session session) => _conversations.send(
    session,
    "Commit the changes on this branch, with a message in this repository's style.",
  );

  /// Asks the agent to push the branch and open its pull request.
  @override
  Future<void> openPullRequest(Session session) => _conversations.send(
    session,
    "Push this branch and open a pull request for it, written in this repository's style. "
    'Tell me its address.',
  );

  /// Follows [session]'s checks, or stops.
  @override
  Future<void> watch(Session session, bool on) async {
    await _sessions.save(session.copyWith(watchChecks: on));
    if (on) unawaited(check(_sessions.byId(session.id) ?? session));
  }

  /// Pull requests seen open: followed until merged or closed, to tell.
  bool _open(Session s) => _states[s.id]?.pr?.state == 'OPEN';

  void _plan() {
    final any = _sessions.sessions.any((s) => s.watchChecks || _open(s));
    if (any && _timer == null) {
      _timer = Timer.periodic(every, (_) => unawaited(_checkAll()));
    } else if (!any) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _checkAll() async {
    _ticks++;
    for (final s in _sessions.sessions.toList()) {
      if (s.watchChecks) {
        await check(s);
      } else if (_open(s) && _ticks % 5 == 0) {
        await refresh(s);
      }
    }
  }

  /// Looks at [session]'s checks once; tells what finished, if not told yet.
  @override
  Future<void> check(Session session) async {
    final s = await refresh(session);
    final pr = s?.pr;
    if (s == null || pr == null || !s.checksDone || pr.checks.isEmpty) return;
    if (_told[session.id] == s.head) return;
    _told[session.id] = s.head;
    final failed = s.failed;
    if (failed.isEmpty) {
      await _notify.notify(
        sessionId: session.id,
        title: session.title,
        body: 'Checks passed on #${pr.number}',
        thumbsUp: true,
      );
      return;
    }
    final log = await _shipping.failureLog(session.cwd, s.branch);
    final names = failed.map((c) => c.name).join(', ');
    await _conversations.send(
      _sessions.byId(session.id) ?? session,
      'The checks on pull request #${pr.number} failed: $names.'
      '${log == null ? '' : ' The end of what failed printed:\n\n```\n$log\n```\n'}'
      '\nFix it, commit, and push.',
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_merged.close());
    _sessions.removeListener(_plan);
    super.dispose();
  }
}
