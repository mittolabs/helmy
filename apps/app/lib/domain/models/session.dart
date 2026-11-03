import '../../data/services/snapshots.dart';
import 'engine.dart';

/// One engine's side of a conversation: its own thread, and how much of the
/// shared transcript it has seen.
class const EngineThread({final String? resumeId, final int seen = 0}) {
  Map<String, Object?> toJson() => {'resumeId': resumeId, 'seen': seen};

  static EngineThread fromJson(Map<String, Object?> json) => EngineThread(
    resumeId: json['resumeId'] as String?,
    seen: (json['seen'] as num?)?.toInt() ?? 0,
  );
}

/// One conversation in a working folder. Any engine may answer any message.
class const Session({
  required final String id,
  required final String title,
  required final String cwd,
  required final PermissionLevel level,
  required final DateTime createdAt,
  required final DateTime updatedAt,
  final Map<String, EngineThread> threads = const {},

  /// The engine that answered last, which the next message stays on unless
  /// another has clearly more room.
  final String? lastEngineId,

  /// The folder as it was when the session first sent a message, when it is a
  /// git repository: what the changes panel compares with.
  final Snapshot? baseline,

  /// Kept at the top of the list.
  final bool pinned = false,

  /// Out of the list unless asked for; nothing is deleted.
  final bool archived = false,

  /// The scheduled task this session is a run of, if any.
  final String? taskId,
}) {
  Session copyWith({
    String? title,
    String? cwd,
    PermissionLevel? level,
    DateTime? updatedAt,
    Map<String, EngineThread>? threads,
    String? lastEngineId,
    bool? pinned,
    bool? archived,
    Snapshot? baseline,
  }) => Session(
    id: id,
    title: title ?? this.title,
    cwd: cwd ?? this.cwd,
    level: level ?? this.level,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    threads: threads ?? this.threads,
    lastEngineId: lastEngineId ?? this.lastEngineId,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
    baseline: baseline ?? this.baseline,
    taskId: taskId,
  );

  Session withThread(String engineId, EngineThread thread) =>
      copyWith(threads: {...threads, engineId: thread});

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'cwd': cwd,
    'level': level.id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'threads': {for (final e in threads.entries) e.key: e.value.toJson()},
    'lastEngineId': lastEngineId,
    'pinned': pinned,
    'archived': archived,
    if (baseline != null) 'baseline': baseline!.toJson(),
    'taskId': ?taskId,
  };

  static Session fromJson(Map<String, Object?> json) {
    final threads = <String, EngineThread>{
      for (final e in ((json['threads'] as Map?) ?? const {}).entries)
        '${e.key}': EngineThread.fromJson((e.value as Map).cast<String, Object?>()),
    };
    // Sessions from the build where one engine ran a whole session.
    final oldEngine = json['engineId'] as String?;
    final oldResume = json['resumeId'] as String? ?? json['claudeSessionId'] as String?;
    if (threads.isEmpty && oldResume != null) {
      threads[oldEngine ?? 'claude'] = EngineThread(resumeId: oldResume, seen: 1 << 30);
    }
    return Session(
      id: json['id']! as String,
      title: json['title']! as String,
      cwd: json['cwd']! as String,
      level: PermissionLevel.fromId(
        json['level'] as String? ?? json['mode'] as String? ?? json['permissionMode'] as String?,
      ),
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      threads: threads,
      lastEngineId: json['lastEngineId'] as String? ?? oldEngine,
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
      baseline: Snapshot.fromJson(json['baseline']),
      taskId: json['taskId'] as String?,
    );
  }
}
