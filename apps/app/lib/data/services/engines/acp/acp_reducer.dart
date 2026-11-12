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
    if (m['method'] == 'elicitation/create' && m['id'] != null) {
      _elicit('${m['id']}', params);
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
        if (backgroundIn(call.result!) case (final id, final file)) {
          call.background ??= BackgroundTask(id, outputFile: file);
        }
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
      // What the step is for, in the agent's words when it gave some; never its title
      // when that is only the command again (OpenCode titles a shell step with it).
      if (raw['description'] case final String d when d.trim().isNotEmpty)
        'description': d
      else if (u['title'] case final String t
          when t.isNotEmpty && t.trim() != '${raw['command'] ?? ''}'.trim())
        'description': t,
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

  /// A question the agent puts as a form (the protocol's elicitation): drawn
  /// with the same card as Claude Code's and Codex's questions. Each field
  /// with choices is a question; a yes or no is one with two; the agent's own
  /// field for "another answer" (key_custom) takes what is typed instead.
  void _elicit(String id, Map<String, Object?> p) {
    final schema = (p['requestedSchema'] as Map?)?.cast<String, Object?>() ?? {};
    final fields = (schema['properties'] as Map?)?.cast<String, Object?>() ?? {};
    final message = '${p['message'] ?? ''}'.trim();
    final questions = <Map<String, Object?>>[];
    for (final MapEntry(:key, :value) in fields.entries) {
      if (value is! Map ||
          (key.endsWith('_custom') &&
              fields.containsKey(key.replaceFirst(RegExp(r'_custom$'), '')))) {
        continue;
      }
      final v = value.cast<String, Object?>();
      final many = v['type'] == 'array';
      final inner = (v['items'] as Map?)?.cast<String, Object?>() ?? {};
      final listed = many ? (inner['anyOf'] ?? inner['oneOf']) : (v['oneOf'] ?? v['anyOf']);
      var options = [
        for (final o in (listed as List? ?? const []).whereType<Map>())
          {
            'label': '${o['title'] ?? o['const']}',
            'description': o['description'],
            'value': o['const'],
          },
      ];
      final plain = many ? inner['enum'] : v['enum'];
      if (options.isEmpty && plain is List) {
        options = [
          for (final e in plain) {'label': '$e', 'value': e},
        ];
      }
      if (options.isEmpty && v['type'] == 'boolean') {
        options = [
          {'label': 'Yes', 'value': true},
          {'label': 'No', 'value': false},
        ];
      }
      // The question itself: its description where it has one (OpenCode puts the
      // short label in the title, "Button color", and the question there), else
      // its title, else the form's message; the label above it.
      final title = '${v['title'] ?? ''}'.trim();
      final about = '${v['description'] ?? ''}'.trim();
      final asked = about.isNotEmpty ? about : (title.isNotEmpty ? title : message);
      questions.add({
        'id': key,
        'question': asked,
        'header': title.isNotEmpty && title != asked ? title : null,
        'multiSelect': many,
        'options': options,
        'number': v['type'] == 'number' || v['type'] == 'integer',
      });
    }
    items.add(
      PermissionPrompt(
        requestId: id,
        toolName: 'AskUserQuestion',
        input: {'questions': questions, 'elicitation': true, 'message': message},
        suggestions: const [],
        toolUseId: p['toolCallId'] as String?,
      ),
    );
  }

  /// [prompt]'s answers in the shape its form asked for.
  static Map<String, Object?> formAnswers(PermissionPrompt prompt) {
    final content = <String, Object?>{};
    for (final q in prompt.questions) {
      final key = '${q['id']}';
      final said = prompt.answers[q['question']];
      if (said == null || said.isEmpty) continue;
      final options = [for (final o in (q['options'] as List? ?? const []).whereType<Map>()) o];
      // Picked labels first (they may hold commas), then what is left was typed.
      var rest = said;
      final picked = <Object?>[];
      for (final o in options) {
        final label = '${o['label']}';
        if (rest == label || rest.startsWith('$label, ') || rest.contains(', $label')) {
          picked.add(o['value']);
          rest = rest
              .replaceFirst(label, '')
              .replaceAll(RegExp(r'^(, )+|(, )+$'), '')
              .replaceAll(', , ', ', ');
        }
      }
      if (q['multiSelect'] == true) {
        content[key] = picked;
      } else if (picked.isNotEmpty) {
        content[key] = picked.first;
      } else if (options.isEmpty) {
        content[key] = q['number'] == true ? (num.tryParse(rest.trim()) ?? rest) : rest;
      }
      if (rest.trim().isNotEmpty && options.isNotEmpty) content['${key}_custom'] = rest.trim();
    }
    return content;
  }

  /// A command the agent moved to its own background, from what the step
  /// returned: its id there, and where it writes what it prints. Agents say
  /// it in their own words; these are the ones known.
  static (String, String?)? backgroundIn(String result) {
    // OpenCode 2.2: "Command moved to the background (shell ID: sh_...).
    // Output is streaming to: /path/sh_....out".
    final id =
        RegExp(r'moved to the background \(shell ID: ([^)\s]+)\)').firstMatch(result)?.group(1) ??
        RegExp(
          r'running in the background[^\n]*?\bID:? ([\w-]+)',
          caseSensitive: false,
        ).firstMatch(result)?.group(1);
    if (id == null) return null;
    final file = RegExp(r'(?:streaming|written|writing) to:? (\S+)').firstMatch(result)?.group(1);
    return (id, file);
  }
}
