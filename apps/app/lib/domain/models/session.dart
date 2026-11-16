import 'snapshot.dart';
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

  /// Out of the list until then, when it comes back as needing you.
  final DateTime? snoozedUntil,

  /// Working in its own copy of a repository: the repository's top folder,
  /// and the branch [cwd] is on. Null otherwise.
  final String? repo,
  final String? branch,

  /// Its pull request's checks are followed: a failure goes to the agent to
  /// fix, a pass to the user.
  final bool watchChecks = false,

  /// A side chat: a question asked beside the session with this id, starting
  /// from what it knows. Shown only there, never in the list.
  final String? sideOf,

  /// A background agent: work the chat [sideOf] handed off to go on beside
  /// it, its answer going back there. Shown only in that chat.
  final bool agent = false,

  /// The connection to start away from, for a second opinion: another than
  /// the one the chat that started it is on. Null for any.
  final String? avoid,

  /// How many tokens its conversation held at its last turn's end, as the
  /// connection measured; null before one has.
  final int? size,

  /// Its standing goal (`/goal`): Helmy keeps the agent going toward it, turn
  /// after turn, until the agent says it is met. Null for none.
  final String? goal,

  /// The goal is kept but not worked toward until resumed.
  final bool goalPaused = false,

  /// Who decides what its agent asks to do (Developer mode): Helmy, the
  /// person, or nobody (everything goes ahead).
  final ApprovalMode approvals = .helmy,

  /// How often it has been opened, halving every two weeks (`openScore`),
  /// as of [openedAt]: search puts the chats opened most lately first.
  final double opens = 0,
  final DateTime? openedAt,

  /// Shared as a read-only link: where, and the gist's id to stop with.
  final String? shareUrl,
  final String? shareId,

  /// The chat this thread is part of (decision `0014`).
  final String? chatId,

  /// The panel beside the conversation as it was left: its tabs, which one
  /// showed, its width and whether it was open. Put back on coming back.
  final Map<String, Object?>? panel,

  /// Held to one connection and model (Developer mode), instead of Helmy
  /// choosing per message; null lets Helmy choose.
  final EnginePin? pin,

  /// One line of what the thread is about and where it stands, kept by Helmy.
  final String? summary,

  /// What the person was writing and has not sent; empty or null for none.
  final String? draft,

  /// The secret in its webhook's address, while it has one; empty or null
  /// for none.
  final String? webhook,

  /// The person is away and wants the work to go on: Helmy decides what it
  /// would otherwise ask, and what it still must ask waits for them while
  /// the agent carries on.
  final bool away = false,
}) {
  /// Events sent to its address arrive as messages.
  bool get hasWebhook => webhook?.isNotEmpty ?? false;

  /// Not named yet by a first message ("New chat", "New thread"; "New session"
  /// before chats).
  bool get untitled => RegExp(r"^New (session|chat|thread)\b").hasMatch(title);

  /// Something written and not sent.
  bool get hasDraft => draft?.trim().isNotEmpty ?? false;

  /// A message has gone: a connection took it up, or the folder was noted as
  /// it stood before the first one.
  bool get sent => threads.isNotEmpty || lastEngineId != null || baseline != null || taskId != null;

  /// Nothing sent and nothing written: not a chat yet, so not listed.
  bool get blank => untitled && !hasDraft && !sent;

  /// In its own working copy, on its own branch.
  bool get ownCopy => repo != null && branch != null;

  /// Snoozed, and not yet due back.
  bool get snoozed => snoozedUntil != null && snoozedUntil!.isAfter(DateTime.now());

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
    DateTime? snoozedUntil,
    bool wake = false,
    String? repo,
    String? branch,
    bool? watchChecks,
    String? chatId,
    Map<String, Object?>? panel,
    EnginePin? pin,

    /// Lets Helmy choose again: [pin] cleared.
    bool unpin = false,
    String? summary,

    /// '' clears it.
    String? draft,

    /// '' turns it off.
    String? webhook,
    bool? away,
    bool? agent,
    String? avoid,
    int? size,
    String? goal,
    bool? goalPaused,
    ApprovalMode? approvals,
    double? opens,
    DateTime? openedAt,
    String? shareUrl,
    String? shareId,

    /// No longer shared.
    bool unshare = false,

    /// Drops [goal]: met, or cleared.
    bool clearGoal = false,

    /// Drops [baseline], for a session moved to another folder: the next
    /// message takes the new folder's.
    bool rebase = false,
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
    baseline: rebase ? null : baseline ?? this.baseline,
    taskId: taskId,
    snoozedUntil: wake ? null : snoozedUntil ?? this.snoozedUntil,
    repo: repo ?? this.repo,
    branch: branch ?? this.branch,
    watchChecks: watchChecks ?? this.watchChecks,
    sideOf: sideOf,
    chatId: chatId ?? this.chatId,
    panel: panel ?? this.panel,
    pin: unpin ? null : pin ?? this.pin,
    summary: summary ?? this.summary,
    draft: draft ?? this.draft,
    webhook: webhook ?? this.webhook,
    away: away ?? this.away,
    agent: agent ?? this.agent,
    avoid: avoid ?? this.avoid,
    size: size ?? this.size,
    goal: clearGoal ? null : goal ?? this.goal,
    goalPaused: clearGoal ? false : goalPaused ?? this.goalPaused,
    approvals: approvals ?? this.approvals,
    opens: opens ?? this.opens,
    openedAt: openedAt ?? this.openedAt,
    shareUrl: unshare ? null : shareUrl ?? this.shareUrl,
    shareId: unshare ? null : shareId ?? this.shareId,
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
    if (snoozedUntil != null) 'snoozedUntil': snoozedUntil!.toIso8601String(),
    'repo': ?repo,
    'branch': ?branch,
    if (watchChecks) 'watchChecks': true,
    'sideOf': ?sideOf,
    'chatId': ?chatId,
    'panel': ?panel,
    if (pin != null) 'pin': pin!.toJson(),
    'summary': ?summary,
    if (hasDraft) 'draft': draft,
    if (hasWebhook) 'webhook': webhook,
    if (away) 'away': true,
    if (agent) 'agent': true,
    'avoid': ?avoid,
    'size': ?size,
    'goal': ?goal,
    if (goalPaused) 'goalPaused': true,
    if (approvals != .helmy) 'approvals': approvals.name,
    if (opens > 0) 'opens': opens,
    if (openedAt != null) 'openedAt': openedAt!.toIso8601String(),
    'shareUrl': ?shareUrl,
    'shareId': ?shareId,
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
      snoozedUntil: DateTime.tryParse('${json['snoozedUntil'] ?? ''}'),
      repo: json['repo'] as String?,
      branch: json['branch'] as String?,
      watchChecks: json['watchChecks'] == true,
      sideOf: json['sideOf'] as String?,
      chatId: json['chatId'] as String?,
      panel: (json['panel'] as Map?)?.cast<String, Object?>(),
      pin: EnginePin.fromJson(json['pin']),
      summary: json['summary'] as String?,
      draft: json['draft'] as String?,
      webhook: json['webhook'] as String?,
      away: json['away'] == true,
      agent: json['agent'] == true,
      avoid: json['avoid'] as String?,
      size: (json['size'] as num?)?.toInt(),
      goal: json['goal'] as String?,
      goalPaused: json['goalPaused'] == true,
      approvals:
          ApprovalMode.values.where((a) => a.name == json['approvals']).firstOrNull ?? .helmy,
      opens: (json['opens'] as num?)?.toDouble() ?? 0,
      openedAt: DateTime.tryParse('${json['openedAt'] ?? ''}'),
      shareUrl: json['shareUrl'] as String?,
      shareId: json['shareId'] as String?,
    );
  }
}
