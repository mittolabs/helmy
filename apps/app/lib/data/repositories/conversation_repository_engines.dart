import 'dart:async';
import 'dart:io';

import '../../domain/models/chat_item.dart';
import '../../domain/models/engine.dart';
import '../../domain/models/permission_rule.dart';
import '../../domain/models/session.dart';
import '../../utils/result.dart';
import '../services/engines/agent_engine.dart';
import '../services/engines/decider.dart';
import '../services/engines/engine_registry.dart';
import '../services/engines/ollama/ollama_chat_engine.dart';
import '../services/engines/engine_router.dart';
import '../services/engines/handoff.dart';
import '../services/engines/needs.dart';
import '../services/engines/usage_meter.dart';
import '../services/snapshots.dart';
import '../services/storage_service.dart';
import 'conversation_repository.dart';
import 'session_repository.dart';

/// A message on its way: which engine has it, where its output starts, and
/// which engines already failed it.
class _Turn {
  new(this.text, this.start, {this.attachments = const [], Set<Capability> needs = const {}})
    : needs = {...needsOf(text), ...needs};
  final String text;
  final List<String> attachments;

  /// What it needs that only some engines have; a turn that needs something is
  /// a detour, and the session goes back to its own engine afterwards.
  final Set<Capability> needs;
  final int start;
  final Set<String> tried = {};
  String? engineId;

  /// Begun by the agent itself, not by a message: it is never sent elsewhere.
  bool unasked = false;

  /// Whether the model on this Mac has been asked about it yet.
  bool decided = false;
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
  }) : _enabled = enabled ?? ((_) => true),
       _rules = rules ?? (() => const []);

  /// Takes the folder's state before each message, when it is a git repository.
  final Snapshots? _snapshots;

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
    notifyListeners();
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
  }) async {
    final c = of(session.id);
    // Written while the agent works: it waits, and goes when the turn ends.
    if (c.busy) {
      c.queue.add((text: text, attachments: attachments, needs: needs));
      notifyListeners();
      return const .ok(null);
    }
    // Busy from here, before anything is awaited: a message sent meanwhile waits.
    c.busy = true;
    notifyListeners();
    // The folder as it is before this message, and before the session's first.
    final checkpoint = await _snapshots?.take(session.cwd);
    if (checkpoint != null && session.baseline == null) {
      session = session.copyWith(baseline: checkpoint);
      await _sessions.save(session);
    }
    if (text.startsWith('!') && text.trim().length > 1) {
      return _shell(session, text.substring(1).trim(), checkpoint);
    }
    c.items.add(
      UserMessage(text, attachments: attachments)
        ..sentAt = DateTime.now()
        ..checkpoint = checkpoint
        ..branches = _branching.remove(session.id),
    );
    c.busy = true;
    notifyListeners();

    var updated = session.copyWith(updatedAt: DateTime.now());
    if (session.title.startsWith('New session')) {
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
  Future<void> _decide(_Turn turn) async {
    turn.decided = true;
    if (turn.text.startsWith('/') || turn.attachments.isNotEmpty) {
      turn.needs.add(Capability.tools);
      return;
    }
    var offline = true;
    for (final e in _engines.engines) {
      if (e.info.localOnly || !_enabled(e.info.id) || _meter.isDown(e.info.id)) continue;
      if (await e.unavailableReason() == null) {
        offline = false;
        break;
      }
    }
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
      // A local model only answers when nothing online can; and then, for a
      // message that needs no tools, the one answering directly does.
      final online = [
        for (final e in candidates)
          if (!e.localOnly) e,
      ];
      final plain = [
        for (final e in candidates)
          if (!e.capabilities.contains(Capability.tools)) e,
      ];
      final id = _router.choose(
        candidates: online.isNotEmpty
            ? online
            : !turn.needs.contains(Capability.tools) && plain.isNotEmpty
            ? plain
            : candidates,
        current: session.lastEngineId,
        needs: turn.needs,
      );
      if (id == null) {
        c
          ..busy = false
          ..thinking = false;
        c.items.add(
          Notice(
            _engines.engines.isEmpty || turn.tried.isEmpty
                ? 'No agent is available. Install Claude Code or Codex and log in, then try again.'
                : 'No agent could take this message right now. Try again in a little while.',
          ),
        );
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
      run.send('${handoff(missed)}${turn.text}', attachments: turn.attachments);
      return;
    }
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
          level: session.level,
          resumeId: session.threads[engineId]?.resumeId,
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
    _applyRules(sessionId, run);
    _meter.report(engineId, run.status.usage);
    final turn = _turns[sessionId];
    if (ended && turn != null && turn.engineId == engineId) {
      if (!turn.unasked && _failedClean(c, turn)) {
        final askedForTools = c.items
            .skip(turn.start)
            .whereType<TurnSummary>()
            .any((t) => t.error == needsToolsError);
        // Take back what the failure left and let another engine have the message.
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
      _finish(sessionId, engineId, run);
    }
    notifyListeners();
  }

  void _finish(String sessionId, String engineId, EngineRun run) {
    final c = of(sessionId)
      ..busy = false
      ..thinking = false;
    final turn = _turns.remove(sessionId);
    for (final p in c.items.whereType<PermissionPrompt>()) {
      if (p.decision == .pending) p.decision = .cancelled;
    }
    final session = _sessions.byId(sessionId);
    if (session != null) {
      final thread = EngineThread(resumeId: run.status.resumeId, seen: c.items.length);
      // A detour for a capability leaves the session on its own engine, which
      // hears what happened through the handoff next time.
      final detour =
          turn != null &&
          (turn.needs.any((n) => n != Capability.tools) || turn.unasked) &&
          session.lastEngineId != null;
      _sessions.save(
        detour
            ? session.withThread(engineId, thread)
            : session.withThread(engineId, thread).copyWith(lastEngineId: engineId),
      );
    }
    _persist(sessionId);
    _next(sessionId);
  }

  /// Sends the next message that waited for this turn, if any.
  void _next(String sessionId) {
    final c = of(sessionId);
    final session = _sessions.byId(sessionId);
    if (c.busy || c.queue.isEmpty || session == null) return;
    final q = c.queue.removeAt(0);
    unawaited(send(session, q.text, attachments: q.attachments, needs: q.needs));
  }

  /// Answers, without asking, any approval a rule in settings covers.
  void _applyRules(String sessionId, EngineRun run) {
    final rules = _rules();
    if (rules.isEmpty) return;
    for (final p in of(sessionId).items.whereType<PermissionPrompt>()) {
      if (p.decision != .pending || !rules.any((r) => r.allows(p))) continue;
      run.answer(p, .allow);
      p.decision = .allowedByRule;
    }
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
    try {
      final r = await Process.run(Platform.environment['SHELL'] ?? '/bin/zsh', [
        '-lc',
        command,
      ], workingDirectory: session.cwd).timeout(const Duration(minutes: 2));
      call
        ..result = '${r.stdout}${r.stderr}'.trimRight()
        ..isError = r.exitCode != 0;
      if (call.result!.isEmpty) {
        call.result = r.exitCode == 0 ? '(no output)' : 'exit ${r.exitCode}';
      }
    } on Object catch (e) {
      call
        ..result = '$e'
        ..isError = true;
    }
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

  @override
  void steer(String sessionId, int index) {
    final c = of(sessionId);
    if (index < 0 || index >= c.queue.length) return;
    c.queue.insert(0, c.queue.removeAt(index));
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
    if (run == null) return .error(Exception('The agent could not start'));
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
      c.items.add(Notice('The agent stopped partway through. Send the message again to go on.'));
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
  void interrupt(String sessionId) => _active(sessionId)?.interrupt();

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
        run.setLevel(level);
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

  static const _explainer =
      'You explain shell commands to a developer in plain words: first what the whole '
      'command does, then each part in one short line as a Markdown list. Mention anything '
      'risky. No preamble. Under 150 words.';

  @override
  Future<Result<String>> explain(String sessionId, ToolCall call) async {
    final command = PermissionRule.plainCommand('${call.input['command'] ?? ''}');
    if (command.trim().isEmpty) return .error(Exception('No command to explain'));
    // The engine with the most room first, then the rest; one on this Mac last.
    final ready = [
      for (final e in _engines.engines)
        if (_enabled(e.info.id)) e,
    ];
    final online = ready.where((e) => !e.info.localOnly).toList();
    final first = online.isEmpty
        ? null
        : _router.choose(
            candidates: [for (final e in online) e.info],
            current: null,
            needs: const {},
          );
    final order = [
      ...online.where((e) => e.info.id == first),
      ...online.where((e) => e.info.id != first),
      ...ready.where((e) => e.info.localOnly),
    ];
    for (final e in order) {
      final answer = await e.ask(_explainer, 'Explain this command:\n\n$command');
      if (answer == null) continue;
      call.explanation = answer;
      await _persist(sessionId);
      notifyListeners();
      return .ok(answer);
    }
    return .error(
      Exception('No agent could answer. Check your connection, or set up a local model.'),
    );
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

  Future<void> _persist(String sessionId) => _storage.write(
    'transcripts/$sessionId.json',
    of(sessionId).items.map((i) => i.toJson()).toList(),
  );

  @override
  void dispose() {
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
