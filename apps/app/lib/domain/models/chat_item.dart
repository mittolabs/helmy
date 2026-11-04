import 'dart:convert';

import 'snapshot.dart';

/// One thing shown in a conversation. Items are mutable while a turn streams
/// in, and serialised so a conversation survives a restart.
sealed class ChatItem {
  Map<String, Object?> toJson();

  static ChatItem fromJson(Map<String, Object?> json) => switch (json['kind']) {
    'user' =>
      UserMessage(
          json['text']! as String,
          attachments: [...((json['attachments'] as List?) ?? const []).whereType<String>()],
        )
        ..checkpoint = Snapshot.fromJson(json['checkpoint'])
        ..branches = Branches.fromJson(json['branches'])
        ..sentAt = DateTime.tryParse('${json['sentAt'] ?? ''}')
        ..from = json['from'] as String?,
    'text' => AssistantText(json['key']! as String, json['text']! as String),
    'tool' => ToolCall.fromJson(json),
    'permission' => PermissionPrompt.fromJson(json),
    'turn' => TurnSummary.fromJson(json),
    'image' => ImageItem(json['path']! as String, json['prompt'] as String?),
    'tasks' => TaskList.fromJson(json),
    _ => Notice(
      json['text'] as String? ?? '',
      fix: json['fix'] as String?,
      details: json['details'] as String?,
    ),
  };
}

class UserMessage extends ChatItem {
  new(this.text, {this.attachments = const []});
  final String text;

  /// Files sent with it, by path.
  final List<String> attachments;

  /// The folder just before this message went, when it is a git repository:
  /// what "undo file changes from here" puts back.
  Snapshot? checkpoint;

  /// When this message replaced another by an edit: every version of the
  /// conversation from here on, this one among them.
  Branches? branches;

  /// When it was sent, as Helmy saw it; unknown for older messages.
  DateTime? sentAt;

  /// Sent by the agent of another thread in its chat, not by the person:
  /// that thread's title.
  String? from;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'user',
    'text': text,
    if (attachments.isNotEmpty) 'attachments': attachments,
    if (checkpoint != null) 'checkpoint': checkpoint!.toJson(),
    if (branches != null) 'branches': branches!.toJson(),
    if (sentAt != null) 'sentAt': sentAt!.toIso8601String(),
    if (from != null) 'from': from,
  };
}

/// The versions of a conversation from one message on, kept when that message
/// was edited. The first message of the version showing holds them.
class Branches {
  new(this.tails, this.active);

  /// Each version's items from the edited message on. The one showing is null:
  /// its items are the conversation's own.
  final List<List<ChatItem>?> tails;

  /// Which version is showing.
  int active;

  int get length => tails.length;

  Map<String, Object?> toJson() => {
    'active': active,
    'tails': [
      for (final t in tails) t == null ? null : [for (final i in t) i.toJson()],
    ],
  };

  static Branches? fromJson(Object? json) {
    if (json is! Map) return null;
    final tails = [
      for (final t in (json['tails'] as List? ?? const []))
        t is List ? [for (final i in t.whereType<Map>()) ChatItem.fromJson(i.cast())] : null,
    ];
    final active = (json['active'] as num?)?.toInt() ?? 0;
    if (active < 0 || active >= tails.length) return null;
    return Branches(tails, active);
  }
}

/// Keeps `items[index..]` as a version of its own and leaves the conversation
/// ending just before [index], ready for the edited message. Returns the
/// branches that message is to hold.
Branches branchAt(List<ChatItem> items, int index) {
  final head = items[index] as UserMessage;
  final b = head.branches ?? Branches([null], 0);
  head.branches = null;
  b.tails[b.active] = items.sublist(index);
  items.removeRange(index, items.length);
  b.tails.add(null);
  b.active = b.tails.length - 1;
  return b;
}

/// Shows version [to] of the branches held by the message at [index].
/// Returns false when there is no such version.
bool switchBranch(List<ChatItem> items, int index, int to) {
  final head = items[index];
  if (head is! UserMessage) return false;
  final b = head.branches;
  if (b == null || to == b.active || to < 0 || to >= b.length) return false;
  final next = b.tails[to];
  if (next == null || next.isEmpty || next.first is! UserMessage) return false;
  head.branches = null;
  b.tails[b.active] = items.sublist(index);
  b.tails[to] = null;
  b.active = to;
  (next.first as UserMessage).branches = b;
  items
    ..removeRange(index, items.length)
    ..addAll(next);
  return true;
}

class AssistantText extends ChatItem {
  new(this.key, this.text);

  /// `messageId:blockIndex`, so stream deltas find their block.
  final String key;
  String text;

  @override
  Map<String, Object?> toJson() => {'kind': 'text', 'key': key, 'text': text};
}

class ToolCall extends ChatItem {
  new({required this.id, required this.name, required this.input});

  final String id;
  final String name;
  final Map<String, Object?> input;
  String? result;
  bool isError = false;

  /// The steps a helper agent took inside this one, when it started a helper.
  final List<ToolCall> children = [];

  /// When the agent moved this step to the background: its task, as the
  /// agent reports it.
  BackgroundTask? background;

  /// Its command in plain words, once asked for.
  String? explanation;

  bool get done => result != null;

  /// The one line that says what the call does, for the collapsed card.
  String get summary {
    String? s(String k) => input[k] is String ? input[k]! as String : null;
    return switch (name) {
      'Bash' => s('description') ?? s('command') ?? '',
      'Shell' => s('command') ?? '',
      'Read' || 'Write' || 'Edit' || 'NotebookEdit' => s('file_path') ?? s('notebook_path') ?? '',
      'Glob' || 'Grep' => s('pattern') ?? '',
      'WebFetch' => s('url') ?? '',
      'WebSearch' => s('query') ?? '',
      'Task' || 'Agent' => s('description') ?? '',
      _ => '',
    };
  }

  String get prettyInput => const JsonEncoder.withIndent('  ').convert(input);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'tool',
    'id': id,
    'name': name,
    'input': input,
    'result': result,
    'isError': isError,
    if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
    if (background != null) 'background': background!.toJson(),
    'explanation': ?explanation,
  };

  static ToolCall fromJson(Map<String, Object?> json) =>
      ToolCall(
          id: json['id']! as String,
          name: json['name']! as String,
          input: (json['input'] as Map?)?.cast<String, Object?>() ?? {},
        )
        ..result = json['result'] as String?
        ..isError = json['isError'] as bool? ?? false
        ..children.addAll([
          for (final c in (json['children'] as List? ?? const []).whereType<Map>())
            ToolCall.fromJson(c.cast()),
        ])
        ..background = BackgroundTask.fromJson(json['background'])
        ..explanation = json['explanation'] as String?;
}

/// Work an agent left running while the conversation goes on: a command, or a
/// helper agent.
class BackgroundTask {
  new(this.id, {this.status = .running, this.outputFile});

  final String id;
  BackgroundStatus status;

  /// Where the agent writes what it prints, when it says.
  String? outputFile;

  Map<String, Object?> toJson() => {'id': id, 'status': status.name, 'outputFile': ?outputFile};

  /// One read back from a saved conversation. A task that was running then is
  /// no longer known: the agent that ran it is not the one running now.
  static BackgroundTask? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    final status = BackgroundStatus.values.asNameMap()[json['status']] ?? .unknown;
    return BackgroundTask(
      json['id']! as String,
      status: status == .running ? .unknown : status,
      outputFile: json['outputFile'] as String?,
    );
  }
}

enum BackgroundStatus {
  running,
  completed,
  failed,
  stopped,

  /// Not followed to its end: the app closed, or the agent did, before it ended.
  unknown;

  /// From the agent's own word for it.
  static BackgroundStatus of(Object? s) => switch (s) {
    'running' || 'pending' => running,
    'completed' => completed,
    'failed' => failed,
    'killed' || 'stopped' => stopped,
    _ => unknown,
  };
}

enum PermissionDecision { pending, allowed, allowedAlways, allowedByRule, denied, cancelled }

/// Claude wants to use a tool and the CLI asked us. Also carries
/// AskUserQuestion, which arrives the same way.
class PermissionPrompt extends ChatItem {
  new({
    required this.requestId,
    required this.toolName,
    required this.input,
    required this.suggestions,
    this.toolUseId,
  });

  final String requestId;
  final String toolName;
  final Map<String, Object?> input;
  final List<Object?> suggestions;
  final String? toolUseId;
  PermissionDecision decision = .pending;

  /// Answers chosen so far, when this is an AskUserQuestion.
  final Map<String, String> answers = {};

  bool get isQuestion => toolName == 'AskUserQuestion';

  List<Map<String, Object?>> get questions => ((input['questions'] as List?) ?? const [])
      .whereType<Map>()
      .map((q) => q.cast<String, Object?>())
      .toList();

  @override
  Map<String, Object?> toJson() => {
    'kind': 'permission',
    'requestId': requestId,
    'toolName': toolName,
    'input': input,
    'toolUseId': toolUseId,
    // A restart ends the process that asked, so a pending prompt cannot be answered.
    'decision': (decision == .pending ? PermissionDecision.cancelled : decision).name,
  };

  static PermissionPrompt fromJson(Map<String, Object?> json) => PermissionPrompt(
    requestId: json['requestId']! as String,
    toolName: json['toolName']! as String,
    input: (json['input'] as Map?)?.cast<String, Object?>() ?? {},
    suggestions: const [],
    toolUseId: json['toolUseId'] as String?,
  )..decision = PermissionDecision.values.byName(json['decision']! as String);
}

/// The end of a turn, with what the CLI reported it cost.
class TurnSummary extends ChatItem {
  new({required this.ok, this.costUsd, this.durationMs, this.error});

  final bool ok;
  final double? costUsd;
  final int? durationMs;
  final String? error;

  /// When the answer finished, as Helmy saw it; unknown for older turns.
  DateTime? endedAt;

  /// The connection that answered (or failed), for a fix that needs it;
  /// never shown.
  String? engineId;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'turn',
    'ok': ok,
    'costUsd': costUsd,
    'durationMs': durationMs,
    'error': error,
    if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
    'engineId': ?engineId,
  };

  static TurnSummary fromJson(Map<String, Object?> json) =>
      TurnSummary(
          ok: json['ok'] as bool? ?? true,
          costUsd: (json['costUsd'] as num?)?.toDouble(),
          durationMs: (json['durationMs'] as num?)?.toInt(),
          error: json['error'] as String?,
        )
        ..endedAt = DateTime.tryParse('${json['endedAt'] ?? ''}')
        ..engineId = json['engineId'] as String?;
}

/// A picture an engine made, kept as the file it saved.
class ImageItem extends ChatItem {
  new(this.path, this.prompt);
  final String path;

  /// The description it was made from, as the engine rewrote it.
  final String? prompt;

  @override
  Map<String, Object?> toJson() => {'kind': 'image', 'path': path, 'prompt': prompt};
}

enum TaskStatus { pending, active, done }

/// The agent's list of what it is doing, as it last stood: Claude's todo list,
/// Codex's plan. One per turn; a newer list replaces it.
class TaskList extends ChatItem {
  new(this.tasks, {this.note});

  final List<({String text, TaskStatus status})> tasks;

  /// Why the list changed, when the agent says.
  final String? note;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'tasks',
    'note': note,
    'tasks': [
      for (final t in tasks) {'text': t.text, 'status': t.status.name},
    ],
  };

  static TaskList fromJson(Map<String, Object?> json) => TaskList([
    for (final t in (json['tasks'] as List? ?? const []).whereType<Map>())
      (
        text: '${t['text']}',
        status: TaskStatus.values.asNameMap()[t['status']] ?? TaskStatus.pending,
      ),
  ], note: json['note'] as String?);
}

class Notice extends ChatItem {
  new(this.text, {this.fix, this.details});
  final String text;

  /// When it tells of a problem: the one action that fixes it (a [Fix]'s
  /// link name), and the raw account.
  final String? fix;
  final String? details;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'notice',
    'text': text,
    'fix': ?fix,
    'details': ?details,
  };
}
