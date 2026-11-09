import 'dart:async';

import '../../domain/models/chat_item.dart';
import '../../domain/models/engine.dart';
import '../../domain/models/permission_rule.dart';
import '../../domain/models/session.dart';
import '../../utils/result.dart';
import '../services/engines/agent_engine.dart';
import '../services/engines/decider.dart';
import '../../domain/folder_move.dart';
import '../../domain/routing.dart';
import '../services/engines/explainer.dart';
import '../services/shell_service.dart';
import '../../domain/problem.dart';
import '../../utils/format.dart';
import '../services/engines/engine_registry.dart';
import '../services/engines/ollama/ollama_chat_engine.dart';
import '../services/engines/engine_router.dart';
import '../services/engines/handoff.dart';
import '../services/engines/needs.dart';
import '../../domain/models/work.dart';
import '../services/engines/usage_meter.dart';
import '../services/snapshots.dart';
import '../services/worktrees.dart';
import '../services/turn_log.dart';
import '../services/storage_service.dart';
import 'conversation_repository.dart';
import 'session_repository.dart';
import '../../utils/platform.dart';
import '../services/approvals.dart';

/// A message on its way: which engine has it, where its output starts, and
/// which engines already failed it.
class _Turn {
  new(this.text, this.start, {this.attachments = const [], Set<Capability> needs = const {}})
    : needs = {...needsOf(text), ...needs} {
    kind = kindOf(text, this.needs);
  }

  /// What kind of work it is, for the connection best at that.
  late final WorkKind? kind;
  final String text;
  final List<String> attachments;

  /// What it needs that only some engines have; a turn that needs something is
  /// a detour, and the session goes back to its own engine afterwards.
  final Set<Capability> needs;
  final int start;
  final startedAt = DateTime.now();
  final Set<String> tried = {};
  String? engineId;

  /// Begun by the agent itself, not by a message: it is never sent elsewhere.
  bool unasked = false;

  /// Whether the model on this Mac has been asked about it yet.
  bool decided = false;

  /// The last failure on the way, and where: when no connection is left to
  /// try, this is the cause the user is told, not a vague "try later".
  String? lastError;
  String? lastEngine;
}

/// Routes every message to an engine and hands the conversation across when the
/// engine changes. Knows nothing about any one engine's protocol.
class ConversationRepositoryEngines extends ConversationRepository {
  new({
    required this._engines,
    required this._router,
    required this._meter,
    required this._storage,
    required this._sessions,
    bool Function(String engineId)? enabled,
    List<PermissionRule> Function()? rules,
    this._snapshots,
    this._decider,
    this._worktrees,
    this._log,
    bool Function(String repo)? ownCopies,
    this.holdMargin = const Duration(seconds: 30),
  }) : _ownCopies = ownCopies ?? ((_) => false),
       _enabled = enabled ?? ((_) => true),
       _rules = rules ?? (() => const []);

  /// Takes the folder's state before each message, when it is a git repository.
  final Snapshots? _snapshots;

  /// What each turn cost, measured (decision `0014`).
  final TurnLog? _log;

  /// How long after a limit resets a held message goes: a reset is not
  /// always to the second.
  final Duration holdMargin;

  /// Messages held while every connection is at its limit, by session.
  final _held = <String, Timer>{};

  /// Runs `!command` in the user's shell.
  final ShellService _shellService = const ShellService();

  /// Explains a step's command in plain words.
  late final _explainer = CommandExplainer(_engines, _router, _enabled);

  /// Gives a session its own working copy of a repository, where the
  /// project asks for that ([_ownCopies]).
  final Worktrees? _worktrees;
  final bool Function(String repo) _ownCopies;

  /// The model on this Mac, asked what a message needs before it is routed.
  final Decider? _decider;

  /// Rules that answer an approval without asking, from settings.
  final List<PermissionRule> Function() _rules;

  /// Engines the user turned off in settings are never chosen.
  final bool Function(String engineId) _enabled;

  final EngineRegistry _engines;
  final EngineRouter _router;
  final UsageMeter _meter;
  final StorageService _storage;
  final SessionRepository _sessions;

  final Map<String, Conversation> _conversations = {};

  /// Keyed `sessionId/engineId`.
  final Map<String, EngineRun> _runs = {};

  /// The versions an edited message is to hold, until `send` adds it.
  final Map<String, Branches> _branching = {};
  final Map<String, StreamSubscription<bool>> _subscriptions = {};
  final Map<String, _Turn> _turns = {};

  static String _key(String sessionId, String engineId) => '$sessionId/$engineId';

  @override
  Conversation of(String sessionId) => _conversations.putIfAbsent(sessionId, Conversation.new);

  @override
  Future<void> load(String sessionId) async {
    final c = of(sessionId);
    if (c.loaded) return;
    c.loaded = true;
    final raw = await _storage.read('transcripts/$sessionId.json');
    c.items.insertAll(
      0,
      ((raw as List?) ?? const []).whereType<Map>().map(
        (j) => ChatItem.fromJson(j.cast<String, Object?>()),
      ),
    );
    // A message held for room when Helmy last closed was never sent: said,
    // rather than leaving "goes by itself" standing.
    if (c.items.lastOrNull case Notice(fix: final fix) when fix == Fix.wait.link) {
      c.items.add(
        Notice(
          'Helmy closed while this message waited for room, so it was not sent.',
          fix: Fix.retry.link,
        ),
      );
    }
    // Read for a row in the list, it may arrive after the app has closed.
    if (!_disposed) notifyListeners();
  }

  @override
  Future<String> searchText(String sessionId) async {
    final c = _conversations[sessionId];
    final items = c != null && c.loaded
        ? c.items
        : [
            for (final j
                in ((await _storage.read('transcripts/$sessionId.json') as List?) ?? const [])
                    .whereType<Map>())
              ChatItem.fromJson(j.cast<String, Object?>()),
          ];
    return [
      for (final i in items)
        if (i is UserMessage) i.text else if (i is AssistantText) i.text,
    ].join(' ');
  }

  @override
  Future<Result<void>> send(
    Session session,
    String text, {
    List<String> attachments = const [],
    Set<Capability> needs = const {},
    String? from,
  }) async {
    final c = of(session.id);
    // Written while the agent works: it waits, and goes when the turn ends.
    if (c.busy) {
      c.queue.add((text: text, attachments: attachments, needs: needs, from: from));
      notifyListeners();
      return const .ok(null);
    }
    // Busy from here, before anything is awaited: a message sent meanwhile waits.
    c.busy = true;
    notifyListeners();
    // A session's first message, in a repository that gives each session its
    // own copy: the copy is made now, on a branch named from the message.
    String? copied;
    if (c.items.whereType<UserMessage>().isEmpty && !session.ownCopy && _worktrees != null) {
      final repo = await _worktrees.repoOf(session.cwd);
      if (repo != null && _ownCopies(repo)) {
        final made = await _worktrees.create(repo, text);
        if (made.path != null) {
          session = session.copyWith(cwd: made.path, repo: repo, branch: made.branch);
          await _sessions.save(session);
          copied =
              'Working on my own branch, ${made.branch}, in a copy of ${folderName(repo)}: '
              'other threads here are not disturbed.';
        } else {
          copied = "I couldn't make a separate copy, so I'm working in the folder itself.";
        }
      }
    }
    // The folder as it is before this message, and before the session's first.
    final checkpoint = await _snapshots?.take(session.cwd);
    if (checkpoint != null && session.baseline == null) {
      session = session.copyWith(baseline: checkpoint);
      await _sessions.save(session);
    }
    // A !command runs in the shell only when the person typed it, never when
    // another thread's agent sent it.
    if (from == null && text.startsWith('!') && text.trim().length > 1) {
      return _shell(session, text.substring(1).trim(), checkpoint);
    }
    c.items.add(
      UserMessage(text, attachments: attachments)
        ..from = from
        ..sentAt = DateTime.now()
        ..checkpoint = checkpoint
        ..branches = _branching.remove(session.id),
    );
    if (copied != null) c.items.add(Notice(copied));
    c.busy = true;
    notifyListeners();

    var updated = session.copyWith(updatedAt: DateTime.now());
    if (session.untitled) {
      final line = text.trim().split('\n').first;
      updated = updated.copyWith(title: line.length > 60 ? '${line.substring(0, 57)}...' : line);
    }
    await _sessions.save(updated);
    final turn = _turns[session.id] = _Turn(
      text,
      c.items.length,
      attachments: attachments,
      needs: needs,
    );
    await _dispatch(session.id, turn);
    await _persist(session.id);
    return const .ok(null);
  }

  /// Asks the model on this Mac what [turn] needs, before it is routed. Online,
  /// only when that model is already in memory (routing never loads one), and
  /// only for the services it needs, added to what the word rules found.
  /// Offline, also whether a plain answer will do; unless it is sure, the
  /// message needs tools. Commands and shell lines are not asked about.
  bool? _onlyThisMac;

  @override
  bool? get onlyThisMac => _onlyThisMac;

  /// Checks whether any connection online is on and reachable, and returns
  /// true when none is: only the model on this Mac can answer. Run at launch,
  /// when connections change, and before each message is routed.
  Future<bool> checkReach() async {
    var offline = true;
    for (final e in _engines.engines) {
      if (e.info.localOnly || !_enabled(e.info.id) || _meter.isDown(e.info.id)) continue;
      if (await e.unavailableReason() == null) {
        offline = false;
        break;
      }
    }
    // Asked as the app closes, it may come back after: nothing to tell.
    if (_onlyThisMac != offline && !_disposed) {
      _onlyThisMac = offline;
      notifyListeners();
    }
    return offline;
  }

  Future<void> _decide(_Turn turn) async {
    turn.decided = true;
    if (turn.text.startsWith('/') || turn.attachments.isNotEmpty) {
      turn.needs.add(Capability.tools);
      return;
    }
    final offline = await checkReach();
    final d = await _decider?.decide(
      turn.text,
      route: offline,
      onlyIfLoaded: !offline,
      timeout: offline ? const Duration(seconds: 30) : const Duration(seconds: 2),
    );
    if (d != null) turn.needs.addAll(d.services);
    if (d == null || !d.direct) turn.needs.add(Capability.tools);
  }

  /// Sends [turn] to the engine the router picks, trying the next on failure.
  Future<void> _dispatch(String sessionId, _Turn turn) async {
    final c = of(sessionId);
    if (!turn.decided) await _decide(turn);
    while (true) {
      final session = _sessions.byId(sessionId);
      if (session == null) return;
      final candidates = <EngineInfo>[];
      for (final e in _engines.engines) {
        final id = e.info.id;
        if (turn.tried.contains(id) || _meter.isDown(id) || !_enabled(id)) continue;
        if (await e.unavailableReason() != null) continue;
        // Connections are asked only when the message needs one.
        final needsService = turn.needs.any(
          (n) => n != Capability.imageGeneration && n != Capability.tools,
        );
        final connected = needsService ? await e.connected() : const <Capability>{};
        candidates.add(
          connected.isEmpty
              ? e.info
              : EngineInfo(
                  id: e.info.id,
                  name: e.info.name,
                  liveModeSwitch: e.info.liveModeSwitch,
                  localOnly: e.info.localOnly,
                  capabilities: {...e.info.capabilities, ...connected},
                ),
        );
      }
      // A /command goes to an engine that has it, when one does.
      final command = RegExp(r'^/([\w:.-]+)').firstMatch(turn.text)?.group(1);
      if (command != null) {
        final owners = <EngineInfo>[];
        for (final e in candidates) {
          final engine = _engines.byId(e.id)!;
          if ((await engine.commands(session.cwd)).any((c) => c.name == command)) owners.add(e);
        }
        if (owners.isNotEmpty) {
          candidates
            ..clear()
            ..addAll(owners);
        }
      }
      final ended = _lastTurnEnd[session.id];
      final id = _router.choose(
        candidates: eligible(candidates, turn.needs),
        current: session.lastEngineId,
        needs: turn.needs,
        kind: turn.kind,
        // Its connection still holds it in cache: within minutes of its last turn.
        warm: ended != null && DateTime.now().difference(ended) < cacheLife,
      );
      if (id == null) {
        if (await _hold(sessionId, turn)) return;
        c
          ..busy = false
          ..thinking = false;
        if (turn.lastError != null) {
          // Every connection was tried: the last real cause, with its fix.
          c.items.add(
            TurnSummary(ok: false, error: turn.lastError)
              ..engineId = turn.lastEngine
              ..endedAt = DateTime.now(),
          );
        } else if (_engines.engines.isEmpty || turn.tried.isEmpty) {
          c.items.add(
            Notice(
              "I can't answer yet: nothing is set up for me to work with.",
              fix: Fix.setup.link,
            ),
          );
        } else {
          c.items.add(
            Notice(
              'Every connection I can use is busy or at its limit for this message.',
              fix: Fix.retry.link,
            ),
          );
        }
        _turns.remove(sessionId);
        notifyListeners();
        return;
      }
      turn
        ..engineId = id
        ..tried.add(id);
      final run = await _runFor(session, id);
      if (run == null) {
        _meter.markDown(id);
        continue;
      }
      final thread = session.threads[id] ?? const EngineThread();
      // Everything since this engine last took part, up to the new message.
      final from = thread.seen.clamp(0, turn.start - 1);
      final missed = c.items.sublist(from, turn.start - 1);
      run.send(
        '${handoff(missed, summary: session.summary)}${turn.text}',
        attachments: turn.attachments,
      );
      return;
    }
  }

  /// When every connection that could answer is at its usage limit, the
  /// message waits rather than failing: the thread stays busy (what is sent
  /// after it waits its turn), and it goes by itself when the first limit
  /// lifts. The time said is the reset a connection reported, or, when none
  /// said, when Helmy tries again. False when something else stood in the way.
  Future<bool> _hold(String sessionId, _Turn turn) async {
    if (turn.unasked) return false;
    final limited = <(String, DateTime)>[];
    var usable = 0;
    for (final e in _engines.engines) {
      final id = e.info.id;
      if (!_enabled(id) || await e.unavailableReason() != null) continue;
      usable++;
      if (_meter.downUntil(id) case final until?) limited.add((id, until));
    }
    if (usable == 0 || limited.length < usable) return false;
    limited.sort((a, b) => a.$2.compareTo(b.$2));
    final (first, until) = limited.first;
    final reported = _meter.usageOf(first)?.resetsAt == until;
    final c = of(sessionId)
      ..busy = true
      ..thinking = false
      ..heldUntil = until;
    c.items.add(
      Notice(
        reported
            ? 'Every connection I can use is at its usage limit. This message waits here and '
                  'goes by itself ${atTime(until, null)}, when the first one has room again.'
            : "Every connection I can use is at its usage limit, and none said when it frees "
                  'up. This message waits here; I try it again ${atTime(until, null)}.',
        fix: Fix.wait.link,
      ),
    );
    _persist(sessionId);
    _held[sessionId]?.cancel();
    _held[sessionId] = Timer(until.difference(DateTime.now()) + holdMargin, () {
      _held.remove(sessionId);
      if (_disposed || c.heldUntil == null) return;
      c.heldUntil = null;
      turn
        ..tried.clear()
        ..lastError = null;
      notifyListeners();
      unawaited(_dispatch(sessionId, turn));
    });
    notifyListeners();
    return true;
  }

  /// Lets go of a held message: it stays in the conversation, unsent.
  bool _release(String sessionId) {
    final timer = _held.remove(sessionId);
    if (timer == null) return false;
    timer.cancel();
    final c = of(sessionId)
      ..heldUntil = null
      ..busy = false;
    c.items.add(Notice('Not sent: you stopped it while it waited for room.'));
    _turns.remove(sessionId);
    _persist(sessionId);
    notifyListeners();
    _next(sessionId);
    return true;
  }

  Future<EngineRun?> _runFor(Session session, String engineId) async {
    final key = _key(session.id, engineId);
    final existing = _runs[key];
    if (existing != null) return existing;
    final engine = _engines.byId(engineId)!;
    final EngineRun run;
    try {
      run = await engine.start(
        EngineLaunch(
          cwd: session.cwd,
          // Every connection asks Helmy, which decides (Approvals); planning
          // stays read-only until the plan is approved.
          level: session.level == .readOnly ? PermissionLevel.readOnly : PermissionLevel.ask,
          resumeId: session.threads[engineId]?.resumeId,
          sessionId: session.id,
          brief: session.brief,
        ),
        of(session.id).items,
      );
    } on Object {
      return null;
    }
    _runs[key] = run;
    _subscriptions[key] = run.changes.listen(
      (ended) => _onChange(session.id, engineId, run, ended),
      onDone: () => _onExit(session.id, engineId, run),
    );
    return run;
  }

  /// A turn failed before doing anything: safe to give to another engine
  /// without repeating what it did.
  bool _failedClean(Conversation c, _Turn turn) {
    final output = c.items.skip(turn.start);
    final summary = output.whereType<TurnSummary>().lastOrNull;
    final didSomething = output.any(
      (i) => i is ToolCall || (i is AssistantText && i.text.trim().isNotEmpty),
    );
    return (summary == null || !summary.ok) && !didSomething;
  }

  void _onChange(String sessionId, String engineId, EngineRun run, bool ended) {
    final c = of(sessionId);
    if (run.status.startedByItself) {
      run.status.startedByItself = false;
      // A turn the agent began itself, after background work ended: the
      // session works on it like any other, and what you send waits.
      if (_turns[sessionId] == null) {
        _turns[sessionId] = _Turn('', c.items.length)
          ..engineId = engineId
          ..unasked = true;
        c.busy = true;
      }
    }
    c.thinking = run.status.thinking;
    c.context = run.status.context ?? c.context;
    _judgeApprovals(sessionId, run);
    _meter.report(engineId, run.status.usage);
    final turn = _turns[sessionId];
    if (ended && turn != null && turn.engineId == engineId) {
      if (!turn.unasked && _failedClean(c, turn)) {
        final askedForTools = c.items
            .skip(turn.start)
            .whereType<TurnSummary>()
            .any((t) => t.error == needsToolsError);
        // Take back what the failure left and let another engine have the message.
        final failed = c.items.skip(turn.start).whereType<TurnSummary>().lastOrNull;
        if (failed?.error case final error? when error != needsToolsError) {
          turn
            ..lastError = error
            ..lastEngine = engineId;
        }
        c.items.removeRange(turn.start, c.items.length);
        if (askedForTools) {
          turn.needs.add(Capability.tools);
        } else {
          _meter.markDown(engineId);
        }
        unawaited(_dispatch(sessionId, turn));
        notifyListeners();
        return;
      }
      // Which connection it ended on, for a fix that needs it (signing in).
      c.items.skip(turn.start).whereType<TurnSummary>().lastOrNull?.engineId = engineId;
      _finish(sessionId, engineId, run);
    }
    notifyListeners();
  }

  /// How long a provider keeps a thread in its cache, about: minutes, not
  /// hours (decision `0014`). Past it, a thread is read afresh wherever it
  /// goes, so moving it costs no more than staying.
  static const cacheLife = Duration(minutes: 5);

  /// When each thread's last turn ended, while Helmy has been open.
  final _lastTurnEnd = <String, DateTime>{};

  void _finish(String sessionId, String engineId, EngineRun run) {
    _lastTurnEnd[sessionId] = DateTime.now();
    final c = of(sessionId)
      ..busy = false
      ..thinking = false;
    final turn = _turns.remove(sessionId);
    for (final p in c.items.whereType<PermissionPrompt>()) {
      if (p.decision == .pending) p.decision = .cancelled;
    }
    final session = _sessions.byId(sessionId);
    final moveTo = turn == null ? null : _takeFolderMove(c, turn.start, session?.cwd);
    if (session != null) {
      final thread = EngineThread(resumeId: run.status.resumeId, seen: c.items.length);
      // A detour for a capability leaves the session on its own engine, which
      // hears what happened through the handoff next time.
      final detour =
          turn != null &&
          (turn.needs.any((n) => n != Capability.tools) || turn.unasked) &&
          session.lastEngineId != null;
      final saved = detour
          ? session.withThread(engineId, thread)
          : session.withThread(engineId, thread).copyWith(lastEngineId: engineId);
      // Measured, not assumed: where it ran and what it cost.
      if (turn != null) {
        final moved = session.lastEngineId != null && session.lastEngineId != engineId;
        final needed = [
          for (final n in turn.needs)
            if (n != Capability.tools) n.name,
        ];
        unawaited(
          _log?.turn(
            chat: session.chatId,
            thread: session.id,
            connection: engineId,
            moved: moved,
            why: detour
                ? 'needed ${needed.join(', ')}'
                : moved
                ? 'moved from ${session.lastEngineId}'
                : null,
            tokens: run.status.tokens,
            took: DateTime.now().difference(turn.startedAt),
            from: turn.start,
            to: c.items.length,
          ),
        );
      }
      if (moveTo != null) {
        // Another folder: every connection starts afresh there, handed the
        // conversation so far, as after a switch between them.
        // Before the turn's summary, so the turn still reads as done, not stopped.
        final end = c.items.lastIndexWhere((i) => i is TurnSummary);
        c.items.insert(
          end < 0 ? c.items.length : end,
          Notice('Now working in ${tildePath(moveTo)}'),
        );
        _sessions.save(saved.copyWith(cwd: moveTo, threads: const {}, rebase: true));
        _persist(sessionId);
        unawaited(stop(sessionId).then((_) => _next(sessionId)));
        return;
      }
      _sessions.save(saved);
    }
    _persist(sessionId);
    _next(sessionId);
  }

  /// The folder this turn's answer moves the session to, its line taken out
  /// of the answer; null when it names none, names where the session already
  /// is, or names a folder that is not there.
  String? _takeFolderMove(Conversation c, int start, String? cwd) {
    String? named;
    for (final a in c.items.skip(start).whereType<AssistantText>()) {
      final to = folderMoveIn(a.text);
      if (to == null) continue;
      named = to;
      a.text = withoutFolderLines(a.text);
    }
    if (named == null) return null;
    return resolveFolderMove(named, cwd: cwd, home: homeDir);
  }

  /// Sends the next message that waited for this turn, if any.
  void _next(String sessionId) {
    final c = of(sessionId);
    final session = _sessions.byId(sessionId);
    if (c.busy || c.queue.isEmpty || session == null) return;
    final q = c.queue.removeAt(0);
    unawaited(send(session, q.text, attachments: q.attachments, needs: q.needs, from: q.from));
  }

  late final _approvals = Approvals(_engines, _router, _enabled);

  /// Helmy's blocks in a session: in a row, and in all. Past a few, the
  /// person is asked rather than the agent stopped again.
  final _blocks = <String, ({int inRow, int total})>{};

  /// Decides each approval a connection asks for, without asking the person
  /// (`Approvals`): rules kept from before first; then what only looks or
  /// changes the chat's folder, at once; the rest judged against what the
  /// person asked. Only what cannot be undone, or leaves the Mac, is put to
  /// them, as a question. Their own questions and plans stay theirs.
  void _judgeApprovals(String sessionId, EngineRun run) {
    final c = of(sessionId);
    final session = _sessions.byId(sessionId);
    if (session == null) return;
    final rules = _rules();
    for (final p in c.items.whereType<PermissionPrompt>()) {
      if (p.decision != .pending || p.judged) continue;
      p.judged = true;
      if (p.isQuestion || p.toolName == 'ExitPlanMode') continue;
      if (rules.any((r) => r.allows(p))) {
        run.answer(p, .allow);
        p.decision = .allowedByRule;
        continue;
      }
      final call = p.toolUseId == null
          ? null
          : c.items.whereType<ToolCall>().where((t) => t.id == p.toolUseId).lastOrNull;
      final folder = session.cwd;
      // Secrets are the vault's: never read, and never asked about, so no
      // number of tries turns this into a question.
      if (Approvals.offLimits(p) case final why?) {
        try {
          run.answer(p, .deny, why: why);
          p
            ..decision = .blockedByHelmy
            ..why = 'It would have read secrets, which stay in the vault.';
        } on Object {
          p.decision = .cancelled;
        }
        continue;
      }
      // What no wording should get past the person, first: prompt
      // injection's aims (secrets, downloaded code, persistence, an agent's
      // own permissions).
      if (Approvals.mustAsk(p, folder) case final question?) {
        _settleApproval(sessionId, run, p, (verdict: Verdict.ask, why: question));
        continue;
      }
      if (Approvals.atOnce(p, folder, call: call) case final now?) {
        _settleApproval(sessionId, run, p, now);
        continue;
      }
      p.decision = .checking;
      final asked = [
        // The person's own words: not a chat app's turns, which a page
        // could have written.
        for (final m in c.items.whereType<UserMessage>())
          if (m.text.trim().isNotEmpty && !(m.from ?? '').startsWith('app:')) m.text.trim(),
      ];
      unawaited(
        _approvals
            .judge(p, asked: asked, folder: folder)
            .then((j) => _settleApproval(sessionId, run, p, j)),
      );
    }
  }

  void _settleApproval(String sessionId, EngineRun run, PermissionPrompt p, Judgment j) {
    // Answered or ended meanwhile: nothing left to decide.
    if (p.decision != .pending && p.decision != .checking) return;
    var verdict = j.verdict;
    var why = j.why;
    final blocks = _blocks[sessionId] ?? (inRow: 0, total: 0);
    if (verdict == .block) {
      if (blocks.inRow >= 2 || blocks.total >= 19) {
        // Stopped again and again: the person decides.
        verdict = .ask;
        why = 'I keep stopping this: ${why.isEmpty ? 'it looks unsafe' : why} Let it go ahead?';
      }
      _blocks[sessionId] = (inRow: blocks.inRow + 1, total: blocks.total + 1);
    } else if (verdict == .allow) {
      _blocks[sessionId] = (inRow: 0, total: blocks.total);
    }
    p.why = why.isEmpty ? null : why;
    try {
      switch (verdict) {
        case .allow:
          run.answer(p, .allow);
          p.decision = .allowedByHelmy;
        case .block:
          run.answer(
            p,
            .deny,
            why:
                "Helmy didn't allow this: $why Find a safer way to do what the person asked, "
                "or ask them; don't try to get round this.",
          );
          p.decision = .blockedByHelmy;
        case .ask:
          p.decision = .pending;
      }
    } on Object {
      // The run that asked has ended.
      p.decision = .cancelled;
    }
    notifyListeners();
  }

  /// `!command`: run in the session's folder by Helmy itself, no agent.
  /// It goes in the conversation, so the next agent hears what ran and what
  /// it printed.
  Future<Result<void>> _shell(Session session, String command, Snapshot? checkpoint) async {
    final c = of(session.id);
    final call = ToolCall(
      id: 'you-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Bash',
      input: {'command': command, 'by': 'you'},
    );
    c.items
      ..add(
        UserMessage('!$command')
          ..sentAt = DateTime.now()
          ..checkpoint = checkpoint
          ..branches = _branching.remove(session.id),
      )
      ..add(call);
    c.busy = true;
    notifyListeners();
    final ran = await _shellService.run(command, session.cwd);
    call
      ..result = ran.output
      ..isError = ran.failed;
    c.busy = false;
    await _persist(session.id);
    notifyListeners();
    _next(session.id);
    return const .ok(null);
  }

  @override
  Future<List<SlashCommand>> commands(Session session) async {
    final seen = <String>{};
    final all = <SlashCommand>[];
    for (final e in _engines.engines) {
      if (!_enabled(e.info.id)) continue;
      for (final c in await e.commands(session.cwd)) {
        if (seen.add(c.name)) all.add(c);
      }
    }
    all.sort((a, b) => a.name.compareTo(b.name));
    return all;
  }

  /// Sends a waiting message now. While a turn is under way it joins that
  /// turn, and the agent takes it in at its next step without losing its
  /// place; where the agent cannot, or the message needs a service it may not
  /// have, the turn is stopped and the message sent next.
  @override
  void steer(String sessionId, int index) {
    final c = of(sessionId);
    if (index < 0 || index >= c.queue.length) return;
    final q = c.queue[index];
    if (!c.busy) {
      c.queue.insert(0, c.queue.removeAt(index));
      notifyListeners();
      _next(sessionId);
      return;
    }
    unawaited(_steer(sessionId, q));
  }

  Future<void> _steer(String sessionId, Queued q) async {
    final c = of(sessionId);
    final run = _active(sessionId);
    final plain = q.needs.every((n) => n == Capability.tools);
    if (run != null && plain && await run.steer(q.text, attachments: q.attachments)) {
      c.queue.remove(q);
      c.items.add(UserMessage(q.text, attachments: q.attachments)..sentAt = DateTime.now());
      await _persist(sessionId);
      // Closed while it was written: nobody is left to tell.
      if (!_disposed) notifyListeners();
      return;
    }
    if (_disposed || !c.queue.remove(q)) return;
    c.queue.insert(0, q);
    notifyListeners();
    if (c.busy) {
      interrupt(sessionId);
    } else {
      _next(sessionId);
    }
  }

  @override
  void unqueue(String sessionId, int index) {
    final q = of(sessionId).queue;
    if (index >= 0 && index < q.length) q.removeAt(index);
    notifyListeners();
  }

  @override
  Future<Result<void>> compact(Session session) async {
    final c = of(session.id);
    final engineId = session.lastEngineId;
    if (c.busy) return .error(Exception('Still working'));
    if (engineId == null) return .error(Exception('Nothing to compact yet'));
    final run = await _runFor(session, engineId);
    if (run == null) return .error(Exception("I couldn't start on this"));
    c.items.add(Notice('Compacting the conversation to free up context'));
    c.busy = true;
    _turns[session.id] = _Turn('/compact', c.items.length)..engineId = engineId;
    notifyListeners();
    run.compact();
    return const .ok(null);
  }

  void _onExit(String sessionId, String engineId, EngineRun run) {
    final key = _key(sessionId, engineId);
    if (_runs[key] != run) return;
    _runs.remove(key);
    _subscriptions.remove(key);
    final c = of(sessionId);
    final turn = _turns[sessionId];
    if (turn == null || turn.engineId != engineId) return;
    c.thinking = false;
    for (final p in c.items.whereType<PermissionPrompt>()) {
      if (p.decision == .pending) p.decision = .cancelled;
    }
    if (!turn.unasked && _failedClean(c, turn)) {
      c.items.removeRange(turn.start, c.items.length);
      _meter.markDown(engineId);
      unawaited(_dispatch(sessionId, turn));
    } else {
      // It had started working; running it again elsewhere could do things twice.
      c.items.add(Notice('I stopped partway through. Send the message again to go on.'));
      c.busy = false;
      _turns.remove(sessionId);
      _persist(sessionId);
      _next(sessionId);
    }
    notifyListeners();
  }

  EngineRun? _active(String sessionId) {
    final id = _turns[sessionId]?.engineId;
    return id == null ? null : _runs[_key(sessionId, id)];
  }

  @override
  Future<Result<void>> rewind(Session session, int index, String text) async {
    final c = of(session.id);
    if (c.busy) return .error(Exception('Still working on the last message.'));
    if (index < 0 || index >= c.items.length || c.items[index] is! UserMessage) {
      return .error(Exception('No message of yours at $index'));
    }
    // The engines' own threads hold what is being taken back and cannot be cut,
    // so each starts afresh and is handed the conversation up to here.
    await stop(session.id);
    final attachments = (c.items[index] as UserMessage).attachments;
    // What came after stays, as a version of its own to go back to.
    _branching[session.id] = branchAt(c.items, index);
    final fresh = session.copyWith(threads: const {});
    await _sessions.save(fresh);
    await _persist(session.id);
    notifyListeners();
    return send(_sessions.byId(session.id) ?? fresh, text, attachments: attachments);
  }

  @override
  Future<Result<void>> showBranch(Session session, int index, int to) async {
    final c = of(session.id);
    if (c.busy) return .error(Exception('Still working on the last message.'));
    if (!switchBranch(c.items, index, to)) return .error(Exception('No such version'));
    // The engines' threads hold the version left behind: each starts afresh
    // and is handed this one when next asked.
    await stop(session.id);
    await _sessions.save(session.copyWith(threads: const {}));
    await _persist(session.id);
    notifyListeners();
    return const .ok(null);
  }

  @override
  void interrupt(String sessionId) {
    if (_release(sessionId)) return;
    _active(sessionId)?.interrupt();
  }

  @override
  void answerPermission(String sessionId, PermissionPrompt prompt, PermissionAnswer answer) {
    final run = _active(sessionId);
    if (run == null || prompt.decision != .pending) return;
    run.answer(prompt, answer);
    prompt.decision = switch (answer) {
      .allow => .allowed,
      .allowForSession => .allowedAlways,
      .deny => .denied,
    };
    notifyListeners();
  }

  @override
  void answerQuestion(String sessionId, PermissionPrompt prompt) {
    final run = _active(sessionId);
    if (run == null || prompt.decision != .pending) return;
    run.answerQuestion(prompt);
    prompt.decision = .allowed;
    notifyListeners();
  }

  @override
  Future<void> setLevel(String sessionId, PermissionLevel level) async {
    for (final e in _engines.engines) {
      final key = _key(sessionId, e.info.id);
      final run = _runs[key];
      if (run == null) continue;
      if (e.info.liveModeSwitch) {
        run.setLevel(level == .readOnly ? PermissionLevel.readOnly : PermissionLevel.ask);
      } else {
        // Takes the level at launch: the next message starts it again.
        await _close(key);
      }
    }
  }

  Future<void> _close(String key) async {
    final run = _runs.remove(key);
    await _subscriptions.remove(key)?.cancel();
    await run?.close();
  }

  @override
  Future<Result<String>> explain(String sessionId, ToolCall call) async {
    final command = PermissionRule.plainCommand('${call.input['command'] ?? ''}');
    if (command.trim().isEmpty) return .error(Exception('No command to explain'));
    final answer = await _explainer.explain(command);
    if (answer == null) {
      return .error(
        Exception(
          "I couldn't explain this right now. Check your connection, or set up a model on ${Desktop.current.thisComputer} in Settings.",
        ),
      );
    }
    call.explanation = answer;
    await _persist(sessionId);
    notifyListeners();
    return .ok(answer);
  }

  @override
  void stopTask(String sessionId, String taskId) {
    for (final e in _engines.engines) {
      _runs[_key(sessionId, e.info.id)]?.stopTask(taskId);
    }
  }

  @override
  Future<void> stop(String sessionId) async {
    _turns.remove(sessionId);
    // Closing the agents ends what they left running.
    void mark(Iterable<ToolCall> calls) {
      for (final call in calls) {
        if (call.background?.status == .running) call.background!.status = .stopped;
        mark(call.children);
      }
    }

    mark(of(sessionId).items.whereType<ToolCall>());
    of(sessionId)
      ..busy = false
      ..thinking = false;
    notifyListeners();
    for (final key in _runs.keys.where((k) => k.startsWith('$sessionId/')).toList()) {
      await _close(key);
    }
  }

  @override
  Future<void> forget(String sessionId) async {
    await stop(sessionId);
    _conversations.remove(sessionId);
  }

  @override
  Future<void> copy(String from, String to, {required int upTo, required String note}) async {
    await load(from);
    final source = of(from).items;
    final target = of(to)
      ..loaded = true
      ..items.clear();
    // Copies, not the same items: the two conversations go their own ways.
    for (final i in source.take((upTo + 1).clamp(0, source.length))) {
      target.items.add(ChatItem.fromJson(i.toJson()));
    }
    target.items.add(Notice(note));
    await _persist(to);
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> adopt(String to, List<ChatItem> items, {required String note}) async {
    of(to)
      ..loaded = true
      ..items.clear()
      ..items.addAll(items)
      ..items.add(Notice(note));
    await _persist(to);
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist(String sessionId) => _storage.write(
    'transcripts/$sessionId.json',
    of(sessionId).items.map((i) => i.toJson()).toList(),
  );

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final t in _held.values) {
      t.cancel();
    }
    // Processes outlive this object by a moment; nothing they say may reach it.
    for (final s in _subscriptions.values) {
      unawaited(s.cancel());
    }
    for (final r in _runs.values) {
      unawaited(r.close());
    }
    super.dispose();
  }
}
