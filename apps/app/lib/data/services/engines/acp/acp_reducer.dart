import '../../../../domain/models/chat_item.dart';
import '../../../../domain/models/engine.dart';

/// Folds an Agent Client Protocol agent's `session/update` notifications and
/// requests into [ChatItem]s. Pure, so it can be tested on recorded messages.
class AcpReducer {
  new(this.items);

  final List<ChatItem> items;

  bool thinking = false;

  /// How full its context is, as it last reported.
  ContextUse? context;

  /// What the turn under way has cost so far, in dollars, when it says.
  double? cost;

  /// The commands it offers for "/name", as it last listed them.
  List<SlashCommand> commands = const [];

  /// Its options (model, mode), as it last listed them.
  List<Map<String, Object?>> configOptions = const [];

  int _blocks = 0;
  String? _messageId;

  /// Applies one message from the agent.
  void apply(Map<String, Object?> m) {
    final params = (m['params'] as Map?)?.cast<String, Object?>() ?? {};
    if (m['method'] == 'session/request_permission' && m['id'] != null) {
      _permission('${m['id']}', params);
      return;
    }
    if (m['method'] != 'session/update') return;
    final u = (params['update'] as Map?)?.cast<String, Object?>() ?? {};
    switch (u['sessionUpdate']) {
      case 'agent_message_chunk':
        thinking = false;
        final text = _textOf(u['content']);
        if (text.isEmpty) return;
        final id = u['messageId'] as String?;
        final last = items.lastOrNull;
        if (last is AssistantText && (id == null || id == _messageId)) {
          last.text += text;
        } else {
          items.add(AssistantText('${id ?? 'acp'}:${_blocks++}', text));
        }
        _messageId = id;
      case 'agent_thought_chunk':
        thinking = true;
      case 'tool_call':
        thinking = false;
        _messageId = null;
        final call = ToolCall(id: '${u['toolCallId']}', name: nameOf(u), input: inputOf(u));
        items.add(call);
        _settle(call, u);
      case 'tool_call_update':
        final id = '${u['toolCallId']}';
        final call = items.whereType<ToolCall>().where((c) => c.id == id).lastOrNull;
        if (call == null) return;
        call.input.addAll(inputOf(u));
        _settle(call, u);
      case 'plan':
        final entries = (u['entries'] as List? ?? const []).whereType<Map>();
        final list = TaskList([
          for (final e in entries)
            (
              text: '${e['content']}',
              status: switch (e['status']) {
                'completed' => TaskStatus.done,
                'in_progress' => TaskStatus.active,
                _ => TaskStatus.pending,
              },
            ),
        ]);
        final at = items.lastIndexWhere((i) => i is TaskList);
        if (at >= 0 && items.skip(at + 1).every((i) => i is! UserMessage)) {
          items[at] = list;
        } else {
          items.add(list);
        }
      case 'usage_update':
        final used = (u['used'] as num?)?.toInt();
        final size = (u['size'] as num?)?.toInt();
        if (used != null && size != null) context = ContextUse(used: used, window: size);
        final amount = ((u['cost'] as Map?)?['amount'] as num?)?.toDouble();
        if (amount != null) cost = amount;
      case 'available_commands_update':
        commands = [
          for (final c in (u['availableCommands'] as List? ?? const []).whereType<Map>())
            SlashCommand(
              name: '${c['name']}',
              description: '${c['description'] ?? ''}',
              hint: (c['input'] as Map?)?['hint'] as String?,
            ),
        ];
      case 'config_option_update':
        configOptions = [
          for (final o in (u['configOptions'] as List? ?? const []).whereType<Map>())
            o.cast<String, Object?>(),
        ];
    }
  }

  /// The turn ended, as `session/prompt` answered: its stop reason, or the
  /// error it failed with.
  void ended({String? stopReason, String? error}) {
    thinking = false;
    _messageId = null;
    final ok = error == null && stopReason != 'refusal';
    items.add(
      TurnSummary(
        ok: ok,
        costUsd: cost,
        error:
            error ??
            switch (stopReason) {
              'refusal' => 'It declined to answer that.',
              'max_tokens' => null,
              _ => null,
            },
      )..endedAt = DateTime.now(),
    );
    cost = null;
  }

  void _permission(String requestId, Map<String, Object?> params) {
    final tool = (params['toolCall'] as Map?)?.cast<String, Object?>() ?? {};
    final id = tool['toolCallId'] as String?;
    final known = id == null
        ? null
        : items.whereType<ToolCall>().where((c) => c.id == id).lastOrNull;
    items.add(
      PermissionPrompt(
        requestId: requestId,
        toolName: known?.name ?? nameOf(tool),
        input: {...?known?.input, ...inputOf(tool)},
        suggestions: [...?(params['options'] as List?)],
        toolUseId: id,
      ),
    );
  }

  void _settle(ToolCall call, Map<String, Object?> u) {
    switch (u['status']) {
      case 'completed':
        call.result = _resultOf(u) ?? '';
      case 'failed':
        call
          ..isError = true
          ..result = _resultOf(u) ?? 'It failed.';
    }
  }

  /// Helmy's name for a step, so the chat draws it as it draws Claude
  /// Code's: by the protocol's kind of tool.
  static String nameOf(Map<String, Object?> u) => switch (u['kind']) {
    'read' => 'Read',
    'edit' || 'delete' || 'move' => 'Edit',
    'execute' => 'Bash',
    'search' => 'Grep',
    'fetch' => 'WebFetch',
    _ => '${u['title'] ?? u['name'] ?? 'Step'}',
  };

  /// What a step was given, under the names the chat reads.
  static Map<String, Object?> inputOf(Map<String, Object?> u) {
    final raw = (u['rawInput'] as Map?)?.cast<String, Object?>() ?? {};
    final path = (u['locations'] as List?)?.whereType<Map>().firstOrNull?['path'];
    // A change, in the names Claude Code's edits use, so the chat draws it
    // as a diff: the protocol's own diff where it sends one, else the
    // agent's input (OpenCode writes with content, edits with oldString).
    final diff = (u['content'] as List?)
        ?.whereType<Map>()
        .where((c) => c['type'] == 'diff')
        .firstOrNull;
    final edit = u['kind'] == 'edit';
    return {
      ...raw,
      if (edit && diff != null) ...{
        'old_string': '${diff['oldText'] ?? ''}',
        'new_string': '${diff['newText'] ?? ''}',
        'file_path': ?diff['path'],
      } else if (edit && raw['oldString'] is String) ...{
        'old_string': raw['oldString'],
        'new_string': '${raw['newString'] ?? ''}',
      } else if (edit && raw['content'] is String) ...{
        'old_string': '',
        'new_string': raw['content'],
      },
      'file_path': ?path,
      if (raw['filePath'] case final String p) 'file_path': p,
      if (raw['command'] case final String c) 'command': c,
      if (raw['pattern'] case final String p) 'pattern': p,
      if (raw['url'] case final String w) 'url': w,
      if (u['title'] case final String t when t.isNotEmpty) 'description': t,
    };
  }

  static String _textOf(Object? content) {
    if (content is! Map) return '';
    return content['type'] == 'text' ? '${content['text'] ?? ''}' : '';
  }

  static String? _resultOf(Map<String, Object?> u) {
    final parts = <String>[];
    for (final c in (u['content'] as List? ?? const []).whereType<Map>()) {
      switch (c['type']) {
        case 'content':
          final t = _textOf(c['content']);
          if (t.isNotEmpty) parts.add(t);
        case 'diff':
          parts.add('Changed ${c['path']}');
      }
    }
    if (parts.isNotEmpty) return parts.join('\n');
    final raw = u['rawOutput'];
    if (raw is String) return raw;
    if (raw is Map && raw['output'] is String) return raw['output'] as String;
    return null;
  }
}
