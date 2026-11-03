import '../../../../domain/models/chat_item.dart';
import '../../../../domain/models/engine.dart';

/// Folds `codex app-server` notifications and requests into [ChatItem]s. Pure,
/// so it can be tested on recorded messages.
class CodexReducer {
  new(this.items);

  final List<ChatItem> items;

  String? turnId;
  bool thinking = false;

  /// The fuller of its usage windows, as Codex last reported.
  Usage? usage;

  /// What the last request sent against the model's window.
  ContextUse? context;

  /// Returns true when a turn ended.
  bool apply(Map<String, Object?> m) {
    final params = (m['params'] as Map?)?.cast<String, Object?>() ?? {};
    // A request the server makes of us: an approval or a question.
    if (m['id'] != null) {
      _request('${m['id']}', m['method'] as String? ?? '', params);
      return false;
    }
    switch (m['method']) {
      case 'turn/started':
        turnId = (params['turn'] as Map?)?['id'] as String?;
      case 'item/started':
        _started((params['item'] as Map).cast<String, Object?>());
      case 'item/agentMessage/delta':
        final text = _text(params['itemId']);
        text?.text += params['delta'] as String? ?? '';
      case 'item/completed':
        _completed((params['item'] as Map).cast<String, Object?>());
      case 'serverRequest/resolved':
        final id = '${params['requestId']}';
        for (final p in items.whereType<PermissionPrompt>()) {
          if (p.requestId == id && p.decision == .pending) p.decision = .cancelled;
        }
      case 'account/rateLimits/updated':
        final limits = (params['rateLimits'] as Map?)?.cast<String, Object?>();
        Usage? fullest;
        for (final key in const ['primary', 'secondary']) {
          final w = (limits?[key] as Map?)?.cast<String, Object?>();
          final used = (w?['usedPercent'] as num?)?.toDouble();
          if (used == null || (fullest != null && fullest.used >= used / 100)) continue;
          final reset = (w?['resetsAt'] as num?)?.toInt();
          fullest = Usage(
            used: used / 100,
            resetsAt: reset == null ? null : DateTime.fromMillisecondsSinceEpoch(reset * 1000),
          );
        }
        usage = fullest ?? usage;
      case 'turn/plan/updated':
        final steps = (params['plan'] as List? ?? const []).whereType<Map>();
        final list = TaskList([
          for (final s in steps)
            (
              text: '${s['step']}',
              status: switch (s['status']) {
                'inProgress' => TaskStatus.active,
                'completed' => TaskStatus.done,
                _ => TaskStatus.pending,
              },
            ),
        ], note: params['explanation'] as String?);
        final i = items.lastIndexWhere((x) => x is TaskList || x is UserMessage);
        if (i >= 0 && items[i] is TaskList) {
          items[i] = list;
        } else {
          items.add(list);
        }
      case 'thread/tokenUsage/updated':
        final usage = (params['tokenUsage'] as Map?)?.cast<String, Object?>();
        final window = (usage?['modelContextWindow'] as num?)?.toInt();
        final last = (usage?['last'] as Map?)?.cast<String, Object?>();
        final used = (last?['inputTokens'] as num?)?.toInt();
        if (window != null && window > 0 && used != null) {
          context = ContextUse(used: used, window: window);
        }
      case 'error':
        if (params['willRetry'] != true) {
          final error = (params['error'] as Map?)?['message'] as String?;
          if (error != null) items.add(Notice(error));
        }
      case 'turn/completed':
        thinking = false;
        final turn = (params['turn'] as Map?)?.cast<String, Object?>() ?? {};
        final status = turn['status'];
        if (status == 'interrupted') items.add(Notice('Interrupted'));
        items.add(
          TurnSummary(
            ok: status != 'failed',
            durationMs: (turn['durationMs'] as num?)?.toInt(),
            error: status == 'failed'
                ? ((turn['error'] as Map?)?['message'] as String? ?? 'The turn failed')
                : null,
          )..endedAt = DateTime.now(),
        );
        turnId = null;
        return true;
    }
    return false;
  }

  AssistantText? _text(Object? id) =>
      items.whereType<AssistantText>().where((t) => t.key == id).lastOrNull;

  ToolCall? _call(Object? id) => items.whereType<ToolCall>().where((c) => c.id == id).lastOrNull;

  void _started(Map<String, Object?> item) {
    final id = item['id']! as String;
    switch (item['type']) {
      case 'agentMessage':
        items.add(AssistantText(id, item['text'] as String? ?? ''));
      case 'plan':
        items.add(AssistantText(id, item['text'] as String? ?? ''));
      case 'reasoning':
        thinking = true;
      case 'commandExecution' ||
          'fileChange' ||
          'mcpToolCall' ||
          'webSearch' ||
          'dynamicToolCall' ||
          'collabAgentToolCall' ||
          'imageGeneration':
        if (_call(id) == null) items.add(_toolCall(item));
    }
  }

  void _completed(Map<String, Object?> item) {
    final id = item['id']! as String;
    switch (item['type']) {
      case 'agentMessage' || 'plan':
        final text = _text(id);
        if (text == null) {
          items.add(AssistantText(id, item['text'] as String? ?? ''));
        } else {
          text.text = item['text'] as String? ?? text.text;
        }
      case 'reasoning':
        thinking = false;
      case 'imageGeneration':
        var call = _call(id);
        if (call == null) items.add(call = _toolCall(item));
        final path = item['savedPath'] as String?;
        final failure = item['failure'];
        call
          ..isError = path == null
          ..result = path ?? '${failure ?? item['status']}';
        // The picture is shown from its file; the inline copy is not kept.
        if (path != null) items.add(ImageItem(path, item['revisedPrompt'] as String?));
      case 'commandExecution' ||
          'fileChange' ||
          'mcpToolCall' ||
          'webSearch' ||
          'dynamicToolCall' ||
          'collabAgentToolCall':
        var call = _call(id);
        if (call == null) items.add(call = _toolCall(item));
        final status = item['status'];
        call.isError = status == 'failed' || status == 'declined' || item['error'] != null;
        call.result = switch (item['type']) {
          'commandExecution' =>
            (item['aggregatedOutput'] as String?) ??
                (item['exitCode'] == null ? '$status' : 'exit ${item['exitCode']}'),
          'fileChange' => status == 'completed' ? 'Applied' : '$status',
          'mcpToolCall' => '${item['error'] ?? item['result'] ?? status}',
          _ => '$status',
        };
    }
  }

  ToolCall _toolCall(Map<String, Object?> item) {
    final id = item['id']! as String;
    return switch (item['type']) {
      'commandExecution' => ToolCall(
        id: id,
        name: 'Shell',
        input: {'command': item['command'], 'cwd': item['cwd']},
      ),
      'fileChange' => ToolCall(
        id: id,
        name: 'Edit',
        input: {
          'file_path': [
            for (final c in (item['changes'] as List? ?? const []).whereType<Map>()) c['path'],
          ].join(', '),
          'changes': item['changes'],
        },
      ),
      'mcpToolCall' => ToolCall(
        id: id,
        name: '${item['server']}.${item['tool']}',
        input: {'arguments': item['arguments']},
      ),
      'webSearch' => ToolCall(id: id, name: 'WebSearch', input: {'query': item['query']}),
      'collabAgentToolCall' => ToolCall(
        id: id,
        name: 'Agent',
        input: {'description': item['prompt'], 'tool': item['tool']},
      ),
      'imageGeneration' => ToolCall(id: id, name: 'ImageGeneration', input: const {}),
      _ => ToolCall(id: id, name: '${item['tool'] ?? item['type']}', input: item),
    };
  }

  void _request(String id, String method, Map<String, Object?> params) {
    switch (method) {
      case 'item/commandExecution/requestApproval':
        items.add(
          PermissionPrompt(
            requestId: id,
            toolName: 'Shell',
            input: {'command': params['command'], 'cwd': params['cwd'], 'reason': params['reason']},
            suggestions: const ['acceptForSession'],
            toolUseId: params['itemId'] as String?,
          ),
        );
      case 'item/fileChange/requestApproval':
        items.add(
          PermissionPrompt(
            requestId: id,
            toolName: 'Edit',
            input: {'reason': params['reason'], 'grantRoot': params['grantRoot']},
            suggestions: const ['acceptForSession'],
            toolUseId: params['itemId'] as String?,
          ),
        );
      case 'item/tool/requestUserInput':
        // Drawn with the same form as Claude's questions.
        items.add(
          PermissionPrompt(
            requestId: id,
            toolName: 'AskUserQuestion',
            input: {
              'questions': [
                for (final q in (params['questions'] as List? ?? const []).whereType<Map>())
                  {
                    'id': q['id'],
                    'question': q['question'],
                    'header': q['header'],
                    'multiSelect': false,
                    'options': [
                      for (final o in (q['options'] as List? ?? const []).whereType<Map>())
                        {'label': o['label'], 'description': o['description']},
                    ],
                  },
              ],
            },
            suggestions: const [],
            toolUseId: params['itemId'] as String?,
          ),
        );
    }
  }
}
