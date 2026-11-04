import 'dart:convert';
import 'dart:io';

import '../../domain/models/chat_item.dart';

/// One conversation found in a connection's own history.
typedef FoundConversation = ({
  /// The connection account it belongs to: claude, claude-work, codex.
  String engineId,

  /// Its own id there, which continuing it resumes.
  String threadId,
  String cwd,
  String path,
  DateTime updatedAt,
});

/// A folder with conversations to bring in, as the import list shows it.
typedef FoundProject = ({
  String cwd,
  List<FoundConversation> conversations,
  DateTime latest,

  /// Which kinds of connection had them: claude, codex.
  Set<String> kinds,
});

/// A conversation turned into Helmy's, ready to save.
typedef ImportedConversation = ({
  String title,
  List<ChatItem> items,
  DateTime? startedAt,
  DateTime? endedAt,
});

/// Reads the conversations people had in Claude Code and Codex on this
/// Mac, from their own files, to bring them into Helmy: each kept whole and
/// continued where it left off. Only conversations a person had: not
/// Helmy's own runs, nor other programs' automation, nor scratch folders.
class HistoryImport {
  HistoryImport({String? home, this.scratch = _scratchFolders})
    : _home = home ?? Platform.environment['HOME'] ?? '';
  final String _home;

  /// Folders a conversation in which is not worth bringing in: temporary
  /// ones, where programs try things out.
  final List<String> scratch;
  static const _scratchFolders = [
    '/private/tmp/',
    '/tmp/',
    '/var/folders/',
    '/private/var/folders/',
  ];

  /// Where Codex sessions come from that a person was at, by "originator".
  static const _peopleCodex = {'codex-tui', 'codex_vscode', 'T3 Code', 'Codex Desktop'};

  bool _scratch(String cwd) => scratch.any(cwd.startsWith);

  /// Every account folder of [kind] here: ~/.claude, and ~/.claude-NAME.
  List<(String, Directory)> _accounts(String kind) {
    final home = Directory(_home);
    if (_home.isEmpty || !home.existsSync()) return const [];
    final out = <(String, Directory)>[];
    final pattern = RegExp('^\\.$kind(-[A-Za-z0-9_-]+)?\$');
    for (final d in home.listSync().whereType<Directory>()) {
      final name = d.path.split('/').last;
      final m = pattern.firstMatch(name);
      if (m == null) continue;
      out.add((m[1] == null ? kind : '$kind${m[1]}', d));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  /// The first [bytes] of a file, as lines, for what a conversation's start
  /// says without reading all of it.
  static List<String> _head(File f, [int bytes = 65536]) {
    try {
      final raf = f.openSync();
      final data = raf.readSync(bytes);
      raf.closeSync();
      final text = utf8.decode(data, allowMalformed: true);
      final lines = text.split('\n');
      if (data.length == bytes) lines.removeLast();
      return lines;
    } on Object {
      return const [];
    }
  }

  static Map<String, Object?>? _json(String line) {
    if (line.trim().isEmpty) return null;
    try {
      final j = jsonDecode(line);
      return j is Map<String, Object?> ? j : null;
    } on Object {
      return null;
    }
  }

  /// Every folder with conversations to bring in, newest first. [known] is
  /// the thread ids Helmy already has, which are left out.
  Future<List<FoundProject>> scan({Set<String> known = const {}}) async {
    final found = <FoundConversation>[];
    for (final (engineId, dir) in _accounts('claude')) {
      final projects = Directory('${dir.path}/projects');
      if (!projects.existsSync()) continue;
      for (final f in projects.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.jsonl')) continue;
        final id = f.path.split('/').last.replaceAll('.jsonl', '');
        if (known.contains(id)) continue;
        String? cwd;
        var person = false;
        for (final line in _head(f)) {
          final j = _json(line);
          if (j == null || j['type'] != 'user' || j['isSidechain'] == true) continue;
          cwd ??= j['cwd'] as String?;
          // Typed in Claude Code itself; not a program running it.
          if (j['entrypoint'] == 'cli' && j['isMeta'] != true) person = true;
          if (cwd != null && person) break;
        }
        if (cwd == null || !person) continue;
        found.add((
          engineId: engineId,
          threadId: id,
          cwd: cwd,
          path: f.path,
          updatedAt: f.lastModifiedSync(),
        ));
      }
    }
    for (final (engineId, dir) in _accounts('codex')) {
      final sessions = Directory('${dir.path}/sessions');
      if (!sessions.existsSync()) continue;
      for (final f in sessions.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.jsonl')) continue;
        // Its first line says who started it; that line carries long
        // instructions, so a generous start, whole only if it is longer.
        final head = _head(f, 262144);
        final meta =
            _json(head.firstOrNull ?? '') ?? _json((await f.readAsLines()).firstOrNull ?? '');
        final p = meta?['payload'];
        if (meta?['type'] != 'session_meta' || p is! Map) continue;
        final id = p['id'] as String?, cwd = p['cwd'] as String?;
        if (id == null || cwd == null || known.contains(id)) continue;
        if (!_peopleCodex.contains(p['originator'])) continue;
        // Counted only with something a person said in it.
        final lines = await f.readAsLines();
        if (codexConversation(lines).items.whereType<UserMessage>().isEmpty) continue;
        found.add((
          engineId: engineId,
          threadId: id,
          cwd: cwd,
          path: f.path,
          updatedAt: f.lastModifiedSync(),
        ));
      }
    }
    final byFolder = <String, List<FoundConversation>>{};
    for (final c in found) {
      if (_scratch(c.cwd) || !Directory(c.cwd).existsSync()) continue;
      (byFolder[c.cwd] ??= []).add(c);
    }
    final out = [
      for (final MapEntry(key: cwd, value: list) in byFolder.entries)
        (
          cwd: cwd,
          conversations: list..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
          latest: list.map((c) => c.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
          kinds: {for (final c in list) c.engineId.startsWith('claude') ? 'claude' : 'codex'},
        ),
    ]..sort((a, b) => b.latest.compareTo(a.latest));
    return out;
  }

  /// [c] read whole and turned into Helmy's; null when it holds nothing a
  /// person said.
  Future<ImportedConversation?> read(FoundConversation c) async {
    final lines = await File(c.path).readAsLines();
    final r = c.engineId.startsWith('claude')
        ? claudeConversation(lines)
        : codexConversation(lines);
    return r.items.whereType<UserMessage>().isEmpty ? null : r;
  }
}

/// Words a person did not type, that a tool put in their place: a slash
/// command's wrapping, a command's output, injected instructions.
bool _injected(String text) {
  final t = text.trimLeft();
  return t.startsWith('<') || t.startsWith('# AGENTS.md') || t.startsWith('Caveat:');
}

String _titleFrom(List<ChatItem> items) {
  final first = items.whereType<UserMessage>().firstOrNull?.text.trim() ?? '';
  final line = first.split('\n').first.trim();
  if (line.isEmpty) return 'Imported conversation';
  return line.length <= 60 ? line : '${line.substring(0, 57)}...';
}

String _resultText(Object? content) => switch (content) {
  final String s => s,
  final List l => [
    for (final p in l.whereType<Map>())
      if (p['type'] == 'text') '${p['text']}',
  ].join('\n'),
  _ => '',
};

/// A Claude Code session file as Helmy's conversation: what was said, the
/// steps with what they gave back, and its title as Claude Code named it.
ImportedConversation claudeConversation(List<String> lines) {
  final items = <ChatItem>[];
  final calls = <String, ToolCall>{};
  String? title;
  DateTime? start, end;
  for (final line in lines) {
    final j = HistoryImport._json(line);
    if (j == null) continue;
    if (j['type'] == 'ai-title') title ??= j['aiTitle'] as String?;
    if (j['type'] == 'summary') title ??= j['summary'] as String?;
    if (j['type'] != 'user' && j['type'] != 'assistant') continue;
    if (j['isSidechain'] == true || j['isMeta'] == true) continue;
    final at = DateTime.tryParse('${j['timestamp'] ?? ''}');
    if (at != null) {
      start ??= at;
      end = at;
    }
    final message = j['message'];
    if (message is! Map) continue;
    final content = message['content'];
    final uuid = '${j['uuid'] ?? items.length}';
    if (j['type'] == 'user') {
      final text = content is String
          ? content
          : [
              for (final p in (content as List? ?? const []).whereType<Map>())
                if (p['type'] == 'text') '${p['text']}',
            ].join('\n');
      for (final p in (content is List ? content : const []).whereType<Map>()) {
        if (p['type'] != 'tool_result') continue;
        final call = calls['${p['tool_use_id']}'];
        if (call == null) continue;
        call
          ..result = _resultText(p['content'])
          ..isError = p['is_error'] == true;
      }
      if (text.trim().isNotEmpty && !_injected(text)) {
        items.add(UserMessage(text)..sentAt = at);
      }
      continue;
    }
    for (final (i, p) in (content as List? ?? const []).whereType<Map>().indexed) {
      switch (p['type']) {
        case 'text' when '${p['text']}'.trim().isNotEmpty:
          items.add(AssistantText('$uuid:$i', '${p['text']}'));
        case 'tool_use':
          final call = ToolCall(
            id: '${p['id']}',
            name: '${p['name']}',
            input: (p['input'] as Map?)?.cast<String, Object?>() ?? const {},
          );
          calls[call.id] = call;
          items.add(call);
      }
    }
  }
  return (title: title ?? _titleFrom(items), items: items, startedAt: start, endedAt: end);
}

/// A Codex session file as Helmy's conversation, its steps named as Helmy
/// names Codex's own: Shell for a command, Edit for a patch.
ImportedConversation codexConversation(List<String> lines) {
  final items = <ChatItem>[];
  final calls = <String, ToolCall>{};
  DateTime? start, end;
  for (final line in lines) {
    final j = HistoryImport._json(line);
    if (j == null || j['type'] != 'response_item') continue;
    final p = j['payload'];
    if (p is! Map) continue;
    final at = DateTime.tryParse('${j['timestamp'] ?? ''}');
    if (at != null) {
      start ??= at;
      end = at;
    }
    switch (p['type']) {
      case 'message':
        final text = [
          for (final c in (p['content'] as List? ?? const []).whereType<Map>())
            if (c['type'] == 'input_text' || c['type'] == 'output_text') '${c['text']}',
        ].join('\n');
        if (text.trim().isEmpty) continue;
        if (p['role'] == 'user' && !_injected(text)) items.add(UserMessage(text)..sentAt = at);
        if (p['role'] == 'assistant') items.add(AssistantText('${p['id'] ?? items.length}', text));
      case 'function_call' || 'custom_tool_call':
        final id = '${p['call_id']}';
        final name = '${p['name']}';
        Map<String, Object?> args;
        try {
          args = (jsonDecode('${p['arguments'] ?? '{}'}') as Map).cast<String, Object?>();
        } on Object {
          args = {'input': p['input'] ?? p['arguments']};
        }
        final command = args['command'] ?? args['cmd'];
        final call = switch (name) {
          'shell' || 'exec_command' || 'shell_command' || 'local_shell' => ToolCall(
            id: id,
            name: 'Shell',
            input: {
              'command': command is List
                  ? (command.length >= 3 ? command.last : command.join(' '))
                  : command,
              'cwd': args['workdir'],
            },
          ),
          'apply_patch' => ToolCall(
            id: id,
            name: 'Edit',
            input: {
              'file_path': [
                for (final m in RegExp(
                  r'^\*\*\* (?:Update|Add|Delete) File: (.+)$',
                  multiLine: true,
                ).allMatches('${p['input'] ?? args['input'] ?? ''}'))
                  m[1],
              ].join(', '),
            },
          ),
          _ => ToolCall(id: id, name: name, input: args),
        };
        calls[id] = call;
        items.add(call);
      case 'function_call_output' || 'custom_tool_call_output':
        final call = calls['${p['call_id']}'];
        if (call == null) continue;
        final out = p['output'];
        var text = out is String ? out : jsonEncode(out);
        try {
          final o = jsonDecode(text);
          if (o is Map && o['output'] is String) text = o['output'] as String;
        } on Object {
          // Plain text already.
        }
        call.result = text;
    }
  }
  return (title: _titleFrom(items), items: items, startedAt: start, endedAt: end);
}
