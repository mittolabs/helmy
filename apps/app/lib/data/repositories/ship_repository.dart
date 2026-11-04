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
class ShipRepository extends ChangeNotifier {
  ShipRepository({
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
  final Map<String, String> _told = {};
  Timer? _timer;

  /// What [sessionId]'s branch was last seen as; null before it was asked.
  BranchState? stateOf(String sessionId) => _states[sessionId];

  /// Asks again where [session]'s branch stands.
  Future<BranchState?> refresh(Session session) async {
    final s = await _shipping.state(session.cwd);
    _states[session.id] = s;
    notifyListeners();
    return s;
  }

  /// Asks the agent to commit the work, in the repository's own style.
  Future<void> commit(Session session) => _conversations.send(
    session,
    "Commit the changes on this branch, with a message in this repository's style.",
  );

  /// Asks the agent to push the branch and open its pull request.
  Future<void> openPullRequest(Session session) => _conversations.send(
    session,
    "Push this branch and open a pull request for it, written in this repository's style. "
    'Tell me its address.',
  );

  /// Follows [session]'s checks, or stops.
  Future<void> watch(Session session, bool on) async {
    await _sessions.save(session.copyWith(watchChecks: on));
    if (on) unawaited(check(_sessions.byId(session.id) ?? session));
  }

  void _plan() {
    final any = _sessions.sessions.any((s) => s.watchChecks);
    if (any && _timer == null) {
      _timer = Timer.periodic(every, (_) => unawaited(_checkAll()));
    } else if (!any) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _checkAll() async {
    for (final s in _sessions.sessions.where((s) => s.watchChecks)) {
      await check(s);
    }
  }

  /// Looks at [session]'s checks once; tells what finished, if not told yet.
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
    _sessions.removeListener(_plan);
    super.dispose();
  }
}
