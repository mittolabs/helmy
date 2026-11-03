import '../../../../domain/models/chat_item.dart';
import '../../../../domain/models/engine.dart';

/// Folds Claude Code's stream-json output into [ChatItem]s. Pure: it never talks
/// to the process, so it can be tested on recorded lines.
class ClaudeReducer {
  new(this.items);

  final List<ChatItem> items;

  String? sessionId;
  String? model;
  bool thinking = false;

  /// The fuller of the five-hour and weekly windows, as the CLI last reported.
  Usage? usage;

  /// What the last request sent against the model's window.
  ContextUse? context;

  String? _messageId;
  final Map<String, int> _textBlocksSeen = {};

  /// Returns true when the turn ended.
  bool apply(Map<String, Object?> m) {
    // A helper agent's own steps go inside the call that started it.
    final parent = m['parent_tool_use_id'];
    if (parent != null) {
      _helper('$parent', m);
      return false;
    }
    switch (m['type']) {
      case 'system' when m['subtype'] == 'init':
        sessionId = m['session_id'] as String? ?? sessionId;
        model = m['model'] as String? ?? model;
      // Work moved to the background: its step says how it stands.
      case 'system' when m['subtype'] == 'task_started' && m['is_backgrounded'] == true:
        final call = _findCall('${m['tool_use_id']}', items.whereType<ToolCall>());
        call?.background = BackgroundTask('${m['task_id']}');
      case 'system' when m['subtype'] == 'task_updated':
        final status = ((m['patch'] as Map?)?['status']);
        final task = _task('${m['task_id']}');
        if (task != null && status != null) task.status = BackgroundStatus.of(status);
      case 'system' when m['subtype'] == 'task_notification':
        final task = _task('${m['task_id']}');
        if (task != null) {
          task
            ..status = BackgroundStatus.of(m['status'])
            ..outputFile = m['output_file'] as String? ?? task.outputFile;
        }
      case 'stream_event':
        _streamEvent((m['event'] as Map).cast<String, Object?>());
      case 'assistant':
        _assistant((m['message'] as Map).cast<String, Object?>());
      case 'user':
        _user((m['message'] as Map).cast<String, Object?>());
      case 'control_request':
        final request = (m['request'] as Map).cast<String, Object?>();
        if (request['subtype'] == 'can_use_tool') {
          items.add(
            PermissionPrompt(
              requestId: m['request_id']! as String,
              toolName: request['tool_name']! as String,
              input: (request['input'] as Map?)?.cast<String, Object?>() ?? {},
              suggestions: (request['permission_suggestions'] as List?) ?? const [],
              toolUseId: request['tool_use_id'] as String?,
            ),
          );
        }
      case 'control_cancel_request':
        for (final p in items.whereType<PermissionPrompt>()) {
          if (p.requestId == m['request_id'] && p.decision == .pending) p.decision = .cancelled;
        }
      case 'rate_limit_event':
        final info = (m['rate_limit_info'] as Map?)?.cast<String, Object?>();
        final windows = (info?['unifiedWindows'] as Map?)?.cast<String, Object?>();
        Usage? fullest;
        for (final w in (windows ?? const {}).values.whereType<Map>()) {
          final used = (w['utilization'] as num?)?.toDouble();
          if (used == null || (fullest != null && fullest.used >= used)) continue;
          final reset = (w['resetsAt'] as num?)?.toInt();
          fullest = Usage(
            used: used,
            resetsAt: reset == null ? null : DateTime.fromMillisecondsSinceEpoch(reset * 1000),
          );
        }
        usage = fullest ?? usage;
      case 'result':
        thinking = false;
        _context(m);
        sessionId = m['session_id'] as String? ?? sessionId;
        final isError = m['is_error'] == true || m['subtype'] != 'success';
        final interrupted = m['subtype'] == 'error_during_execution';
        items.add(
          TurnSummary(
            ok: !isError || interrupted,
            costUsd: (m['total_cost_usd'] as num?)?.toDouble(),
            durationMs: (m['duration_ms'] as num?)?.toInt(),
            error: interrupted
                ? null
                : isError
                ? (m['result'] as String? ??
                      (m['errors'] as List?)?.join('\n') ??
                      '${m['subtype']}')
                : null,
          )..endedAt = DateTime.now(),
        );
        for (final p in items.whereType<PermissionPrompt>()) {
          if (p.decision == .pending) p.decision = .cancelled;
        }
        return true;
    }
    return false;
  }

  /// One task list per turn: a newer one replaces the turn's last.
  void _setTasks(TaskList list) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is UserMessage) break;
      if (item is TaskList) {
        items[i] = list;
        return;
      }
    }
    items.add(list);
  }

  /// The last request's input, cached and not, is what the context held.
  void _context(Map<String, Object?> result) {
    final usage = (result['usage'] as Map?)?.cast<String, Object?>();
    final last = (usage?['iterations'] as List?)?.whereType<Map>().lastOrNull;
    final models = (result['modelUsage'] as Map?)?.values.whereType<Map>();
    final window = models
        ?.map((m) => (m['contextWindow'] as num?)?.toInt() ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (last == null || window == null || window == 0) return;
    int n(String k) => (last[k] as num?)?.toInt() ?? 0;
    context = ContextUse(
      used: n('input_tokens') + n('cache_read_input_tokens') + n('cache_creation_input_tokens'),
      window: window,
    );
  }

  /// Files a helper agent's step, or its result, under the call that started it.
  void _helper(String parentId, Map<String, Object?> m) {
    final parent = _findCall(parentId, items.whereType<ToolCall>());
    if (parent == null) return;
    final content = (m['message'] as Map?)?['content'];
    if (content is! List) return;
    for (final raw in content.whereType<Map>()) {
      final block = raw.cast<String, Object?>();
      if (m['type'] == 'assistant' && block['type'] == 'tool_use') {
        parent.children.add(
          ToolCall(
            id: '${block['id']}',
            name: '${block['name']}',
            input: (block['input'] as Map?)?.cast<String, Object?>() ?? {},
          ),
        );
      } else if (m['type'] == 'user' && block['type'] == 'tool_result') {
        final child = parent.children.where((c) => c.id == block['tool_use_id']).lastOrNull;
        child
          ?..result = _resultText(block['content'])
          ..isError = block['is_error'] == true;
      }
    }
  }

  /// The background task with [id], by the step that started it.
  BackgroundTask? _task(String id) {
    BackgroundTask? find(Iterable<ToolCall> calls) {
      for (final c in calls) {
        if (c.background?.id == id) return c.background;
        final inner = find(c.children);
        if (inner != null) return inner;
      }
      return null;
    }

    return find(items.whereType<ToolCall>());
  }

  /// A call by id, among [calls] or inside their helpers' steps.
  static ToolCall? _findCall(String id, Iterable<ToolCall> calls) {
    for (final c in calls) {
      if (c.id == id) return c;
      final inner = _findCall(id, c.children);
      if (inner != null) return inner;
    }
    return null;
  }

  void _streamEvent(Map<String, Object?> e) {
    switch (e['type']) {
      case 'message_start':
        _messageId = (e['message'] as Map?)?['id'] as String?;
      case 'content_block_start':
        final block = (e['content_block'] as Map?)?.cast<String, Object?>() ?? {};
        thinking = block['type'] == 'thinking';
        if (block['type'] == 'text') {
          items.add(AssistantText('$_messageId:${e['index']}', block['text'] as String? ?? ''));
        }
      case 'content_block_delta':
        final delta = (e['delta'] as Map?)?.cast<String, Object?>() ?? {};
        if (delta['type'] == 'text_delta') {
          final key = '$_messageId:${e['index']}';
          final item = _textItems(_messageId).where((t) => t.key == key).lastOrNull;
          item?.text += delta['text'] as String? ?? '';
        }
      case 'content_block_stop':
        thinking = false;
    }
  }

  Iterable<AssistantText> _textItems(String? messageId) =>
      items.whereType<AssistantText>().where((t) => t.key.startsWith('$messageId:'));

  void _assistant(Map<String, Object?> message) {
    final id = message['id'] as String?;
    for (final raw in (message['content'] as List?) ?? const []) {
      final block = (raw as Map).cast<String, Object?>();
      switch (block['type']) {
        case 'text':
          // The complete block is authoritative; it replaces what streamed in.
          final n = _textBlocksSeen[id ?? ''] = (_textBlocksSeen[id ?? ''] ?? 0) + 1;
          final streamed = _textItems(id).toList();
          final text = block['text'] as String? ?? '';
          if (streamed.length >= n) {
            streamed[n - 1].text = text;
          } else if (text.isNotEmpty) {
            items.add(AssistantText('$id:text$n', text));
          }
        case 'tool_use' when block['name'] == 'TodoWrite':
          // Its todo list is shown as the task list, not as a step.
          final todos = ((block['input'] as Map?)?['todos'] as List? ?? const []).whereType<Map>();
          _setTasks(
            TaskList([
              for (final t in todos)
                (
                  text:
                      '${t['status'] == 'in_progress' ? t['activeForm'] ?? t['content'] : t['content']}',
                  status: switch (t['status']) {
                    'in_progress' => TaskStatus.active,
                    'completed' => TaskStatus.done,
                    _ => TaskStatus.pending,
                  },
                ),
            ]),
          );
        case 'tool_use':
          final toolId = block['id']! as String;
          if (!items.any((i) => i is ToolCall && i.id == toolId)) {
            items.add(
              ToolCall(
                id: toolId,
                name: block['name']! as String,
                input: (block['input'] as Map?)?.cast<String, Object?>() ?? {},
              ),
            );
          }
      }
    }
  }

  void _user(Map<String, Object?> message) {
    final content = message['content'];
    if (content is! List) return;
    for (final raw in content) {
      final block = (raw as Map).cast<String, Object?>();
      if (block['type'] == 'tool_result') {
        final call = items
            .whereType<ToolCall>()
            .where((c) => c.id == block['tool_use_id'])
            .lastOrNull;
        if (call == null) continue;
        call
          ..result = _resultText(block['content'])
          ..isError = block['is_error'] == true;
      } else if (block['type'] == 'text') {
        final text = block['text'] as String? ?? '';
        if (text.startsWith('[Request interrupted')) items.add(Notice('Interrupted'));
      }
    }
  }

  static String _resultText(Object? content) => switch (content) {
    String s => s,
    List l =>
      l
          .whereType<Map>()
          .map((b) => b['type'] == 'text' ? b['text'] as String? ?? '' : '[${b['type']}]')
          .join('\n'),
    _ => '',
  };
}
