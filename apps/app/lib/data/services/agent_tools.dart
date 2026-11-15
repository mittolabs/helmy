import 'dart:async';

import '../repositories/conversation_repository.dart';
import '../repositories/session_repository.dart';
import '../../utils/result.dart';
import '../../domain/models/chat_item.dart';
import '../../domain/models/session.dart';

/// Background agents: work a chat hands off to go on beside it, on whichever
/// connection has room (another than the chat's own, for a second opinion).
/// Each is a conversation of its own, shown only in its chat; when it
/// finishes, its answer goes back to the chat as a message from Helmy, so
/// the chat's agent carries on with it.
///
/// The tools, given to every connection: start one, see how they stand (or
/// wait for one), message one, stop one.
class AgentTools {
  AgentTools({required this._sessions, required this._conversations, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _conversations.addListener(_watch);
  }

  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final DateTime Function() _now;

  /// At most this many at work for one chat: each costs its own tokens.
  static const atOnce = 4;

  /// Messages to one agent, when sent: a chat and its agent can keep each
  /// other busy without end, so each is held to [pairLimit] in [pairWindow].
  final _sent = <String, List<DateTime>>{};
  static const pairLimit = 5;
  static const pairWindow = Duration(minutes: 10);

  /// The longest an agent_status call waits for an agent to finish.
  static const longestWait = Duration(seconds: 45);

  static const names = ['agent_start', 'agent_status', 'agent_message', 'agent_stop'];

  static Map<String, Object?> _tool(
    String name,
    String title,
    String description,
    Map<String, Object?> properties,
    List<String> required, {
    bool readOnly = false,
  }) => {
    'name': name,
    'description': description,
    'inputSchema': {'type': 'object', 'properties': properties, 'required': required},
    'annotations': {'readOnlyHint': readOnly, 'title': title},
  };

  static final list = [
    _tool(
      'agent_start',
      'Start a background agent',
      'Starts a background agent: another agent that works on a task beside you, in this '
          'folder, while you go on. Use it for work that can go on alone (a second part of a '
          'build, checking something, a long search), or when the person asks for something to '
          'run in the background. It knows nothing of this conversation: the task must stand on '
          'its own. When it finishes, its answer comes to you as a message. With second_opinion, '
          'it runs on another connection than yours, for an independent look.',
      {
        'title': {'type': 'string', 'description': 'A few words naming the work.'},
        'task': {'type': 'string', 'description': 'The task in full, standing on its own.'},
        'second_opinion': {
          'type': 'boolean',
          'description': 'Run it on another connection than yours.',
        },
      },
      ['title', 'task'],
    ),
    _tool(
      'agent_status',
      'Background agents',
      "How this chat's background agents stand: each one's id, title, whether it is working, "
          'waiting for the person, or done, and its latest words. With id, that one in full: its '
          'answer when done. With wait_seconds (at most 45), waits for it to finish first.',
      {
        'id': {'type': 'string', 'description': 'One agent, by its id.'},
        'wait_seconds': {'type': 'integer', 'description': 'Wait up to this long for it.'},
      },
      [],
      readOnly: true,
    ),
    _tool(
      'agent_message',
      'Message a background agent',
      'Sends a background agent a message: more to do, or a correction. It takes it up after '
          'what it is doing.',
      {
        'id': {'type': 'string', 'description': 'The agent, by its id.'},
        'message': {'type': 'string', 'description': 'What to tell it.'},
      },
      ['id', 'message'],
    ),
    _tool(
      'agent_stop',
      'Stop a background agent',
      'Stops a background agent where it is.',
      {
        'id': {'type': 'string', 'description': 'The agent, by its id.'},
      },
      ['id'],
    ),
  ];

  /// What a chat says to its agent comes from Helmy, never from the person.
  static String fromChat(String chat) => 'Helmy, for "$chat"';

  /// What an agent says back to its chat comes from Helmy, never from the person.
  static String fromAgent(String agent) => 'Helmy, background agent "$agent"';

  /// The background agents of chat [id], oldest first.
  List<Session> agentsOf(String id) => [
    for (final s in _sessions.sessions)
      if (s.agent && s.sideOf == id) s,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// What an agent has said last, whole: its answer once done.
  String answerOf(String id) =>
      _conversations.of(id).items.whereType<AssistantText>().lastOrNull?.text.trim() ?? '';

  /// How an agent stands, in a word.
  String stateOf(String id) {
    final c = _conversations.of(id);
    if (c.pendingPrompts > 0) return 'waiting for the person';
    if (c.busy) return 'working';
    final last = c.items.whereType<TurnSummary>().lastOrNull;
    if (last == null) return 'starting';
    return last.ok ? 'done' : 'stopped';
  }

  // Agents seen working, to tell their chat once each turn ends.
  final _working = <String>{};

  void _watch() {
    for (final s in _sessions.sessions) {
      if (!s.agent) continue;
      final busy = _conversations.of(s.id).busy;
      if (busy) {
        _working.add(s.id);
      } else if (_working.remove(s.id)) {
        unawaited(_report(s));
      }
    }
  }

  /// [agent] finished a turn: its answer to its chat, which carries on with it.
  Future<void> _report(Session agent) async {
    final chat = agent.sideOf == null ? null : _sessions.byId(agent.sideOf!);
    if (chat == null || _disposed) return;
    final state = stateOf(agent.id);
    var answer = answerOf(agent.id);
    if (answer.length > 4000) answer = '${answer.substring(0, 4000)}\n[...]';
    final text = state == 'done'
        ? 'The background agent "${agent.title}" (id ${agent.id}) finished:\n\n'
              '${answer.isEmpty ? '(It said nothing.)' : answer}'
        : 'The background agent "${agent.title}" (id ${agent.id}) stopped before it was done. '
              '${answer.isEmpty ? '' : 'Its last words:\n\n$answer'}';
    await _conversations.load(chat.id);
    if (_disposed) return;
    await _conversations.send(_sessions.byId(chat.id) ?? chat, text, from: fromAgent(agent.title));
  }

  /// Whether [from] may send agent [to] another message now; records it if so.
  bool _allow(String from, String to) {
    final now = _now();
    final times = (_sent['$from>$to'] ??= [])..removeWhere((t) => now.difference(t) > pairWindow);
    if (times.length >= pairLimit) return false;
    times.add(now);
    return true;
  }

  Map<String, Object?> _says(String text, {bool error = false}) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': error,
  };

  Future<Map<String, Object?>> call(String name, Map args, String? session) async {
    final me = session == null ? null : _sessions.byId(session);
    if (me == null) return _says('This conversation is not one Helmy knows.', error: true);
    // An agent's own agents would multiply without end: one level only.
    final chat = me.agent && me.sideOf != null ? _sessions.byId(me.sideOf!) ?? me : me;
    final agents = agentsOf(chat.id);
    Session? one() => agents.where((a) => a.id == '${args['id'] ?? ''}').firstOrNull;

    switch (name) {
      case 'agent_start':
        if (me.agent) {
          return _says(
            'You are a background agent yourself: do the work here, or say what more should be '
            'started in your answer.',
            error: true,
          );
        }
        final title = '${args['title'] ?? ''}'.trim();
        final task = '${args['task'] ?? ''}'.trim();
        if (title.isEmpty || task.isEmpty) {
          return _says('Give it a title and a task.', error: true);
        }
        final running = agents.where((a) => _conversations.of(a.id).busy).length;
        if (running >= atOnce) {
          return _says(
            '$atOnce background agents are already working for this chat. Wait for one to '
            'finish (agent_status), or stop one.',
            error: true,
          );
        }
        final made = await _sessions.create(
          cwd: me.cwd,
          level: me.level,
          title: title,
          sideOf: me.id,
          chatId: me.chatId,
        );
        if (made case Error(:final error)) return _says('It was not started: $error', error: true);
        var agent = (made as Ok<Session>).value.copyWith(
          agent: true,
          away: me.away,
          avoid: args['second_opinion'] == true ? me.lastEngineId : null,
        );
        await _sessions.save(agent);
        agent = _sessions.byId(agent.id) ?? agent;
        _conversations.of(agent.id).loaded = true;
        final sent = await _conversations.send(agent, task, from: fromChat(me.title));
        if (sent case Error(:final error)) {
          return _says('Started, but its task did not go: $error', error: true);
        }
        return _says(
          'Started the background agent "$title" (id ${agent.id}). It works on its own; its '
          'answer comes to you as a message when it finishes. agent_status shows how it stands.',
        );

      case 'agent_status':
        final a = args['id'] == null ? null : one();
        if (args['id'] != null && a == null) {
          return _says('No background agent ${args['id']} in this chat.', error: true);
        }
        if (a == null) {
          if (agents.isEmpty) return _says('This chat has no background agents.');
          return _says(
            [
              for (final x in agents)
                '- "${x.title}" (id ${x.id}): ${stateOf(x.id)}. '
                    '${_firstLine(answerOf(x.id))}',
            ].join('\n'),
          );
        }
        final wait = ((args['wait_seconds'] as num?)?.toInt() ?? 0).clamp(0, longestWait.inSeconds);
        final until = _now().add(Duration(seconds: wait));
        while (_conversations.of(a.id).busy && _now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final state = stateOf(a.id);
        final answer = answerOf(a.id);
        return _says(
          '"${a.title}" (id ${a.id}) is $state.'
          '${answer.isEmpty ? '' : '\n\n${state == 'done' ? 'Its answer' : 'Its latest words'}:\n\n$answer'}',
        );

      case 'agent_message':
        final a = one();
        final message = '${args['message'] ?? ''}'.trim();
        if (a == null) return _says('No background agent ${args['id']} in this chat.', error: true);
        if (message.isEmpty) return _says('Say what to send.', error: true);
        if (!_allow(me.id, a.id)) {
          return _says(
            'You have sent "${a.title}" $pairLimit messages in the last ${pairWindow.inMinutes} '
            'minutes. Wait for its answer, or ask the person.',
            error: true,
          );
        }
        await _conversations.load(a.id);
        final sent = await _conversations.send(a, message, from: fromChat(me.title));
        if (sent case Error(:final error)) return _says('It did not go: $error', error: true);
        return _says(
          'Sent to "${a.title}"${_conversations.of(a.id).busy ? ', which takes it up next' : ''}.',
        );

      case 'agent_stop':
        final a = one();
        if (a == null) return _says('No background agent ${args['id']} in this chat.', error: true);
        _conversations.interrupt(a.id);
        return _says('Stopped "${a.title}".');
    }
    return _says('No such tool.', error: true);
  }

  static String _firstLine(String s) {
    final line = s.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return line.length > 160 ? '${line.substring(0, 160)}...' : line;
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _conversations.removeListener(_watch);
  }
}
