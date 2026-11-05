/// How much the agent may do without asking. The user picks one of these; each
/// engine maps it to its own settings, so nobody has to know which engine runs.
enum PermissionLevel {
  ask('ask', 'Ask first'),
  edit('edit', 'Edit freely'),
  readOnly('read-only', 'Read only'),
  full('full', 'Full access');

  const PermissionLevel(this.id, this.label);
  final String id;
  final String label;

  static PermissionLevel fromId(String? id) => switch (id) {
    // Engine-specific names saved by earlier builds.
    'default' || 'untrusted' => ask,
    'acceptEdits' || 'on-request' => edit,
    'plan' => readOnly,
    'bypassPermissions' || 'full-access' => full,
    _ => values.firstWhere((l) => l.id == id, orElse: () => ask),
  };
}

/// Something only some engines can do. A message that needs one goes to an
/// engine that has it, and the session returns to its own engine afterwards.
enum Capability {
  /// Reading and changing files and running commands: what makes an agent an
  /// agent. Every agent has it; a model answering directly does not.
  tools('read and change files, run commands'),

  /// Making a picture from a description.
  imageGeneration('make images'),

  // Connected services: an engine has one only while it is connected there.
  googleDrive('Google Drive'),
  gmail('Gmail'),
  googleCalendar('Google Calendar'),
  slack('Slack'),
  notion('Notion');

  const Capability(this.label);
  final String label;

  /// The connector a service name stands for, as an engine lists its servers:
  /// "claude.ai Google Drive", "gmail", "slack-mcp".
  static Capability? ofServer(String name) {
    final n = name.toLowerCase();
    if (n.contains('drive')) return googleDrive;
    if (n.contains('gmail') || n.contains('mail')) return gmail;
    if (n.contains('calendar')) return googleCalendar;
    if (n.contains('slack')) return slack;
    if (n.contains('notion')) return notion;
    return null;
  }
}

/// What an engine is and what it can do. For Helmy only: the user never
/// sees an engine.
class const EngineInfo({
  required final String id,

  /// For logs and for the person installing things, not for the chat.
  required final String name,
  final bool liveModeSwitch = false,
  final Set<Capability> capabilities = const {},

  /// Runs on this machine without the internet, and is only chosen when no
  /// other engine can answer: a local model has no limit to run out of, so on
  /// room alone it would always win.
  final bool localOnly = false,

  /// Says nothing of its room or what it is good at (an agent from the ACP
  /// registry), so it answers only the kinds of work it is set best at,
  /// never on room alone.
  final bool assignedOnly = false,
});

/// A command or skill an engine runs when a message starts with /name.
class const SlashCommand({
  required final String name,
  final String description = '',
  final String? hint,

  /// Where the engine keeps it, when it needs telling (Codex skills).
  final String? path,
});

/// How full an engine's context is: what the last request sent against what
/// the model can hold.
class const ContextUse({required final int used, required final int window}) {
  double get fraction => window == 0 ? 0 : used / window;
}

/// One of a connection's usage limits: a session's few hours, or a week.
class const UsageWindow({
  required final String name,
  required final double used,
  final DateTime? resetsAt,

  /// How long the window is, when the connection says.
  final Duration? length,
}) {
  /// How far through the window [now] is (0 to 1): where use "should" be if
  /// it were spread evenly. Null when the window's length or end is unknown.
  double? paceAt(DateTime now) {
    final end = resetsAt, len = length;
    if (end == null || len == null || len == Duration.zero) return null;
    final left = end.difference(now);
    return (1 - left.inSeconds / len.inSeconds).clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'used': used,
    'resetsAt': resetsAt?.toIso8601String(),
    'length': length?.inMinutes,
  };

  static UsageWindow fromJson(Map<String, Object?> json) => UsageWindow(
    name: '${json['name']}',
    used: (json['used'] as num?)?.toDouble() ?? 0,
    resetsAt: DateTime.tryParse('${json['resetsAt']}'),
    length: json['length'] == null ? null : Duration(minutes: (json['length'] as num).toInt()),
  );

  /// A window's name and length from its length in minutes.
  static ({String name, Duration length}) named(int minutes) {
    final d = Duration(minutes: minutes);
    if (minutes >= 7 * 24 * 60) return (name: 'Weekly', length: d);
    if (minutes >= 24 * 60) return (name: 'Daily', length: d);
    final h = minutes / 60;
    return (name: 'Session (${h == h.roundToDouble() ? h.toInt() : h} hours)', length: d);
  }
}

/// How much of an engine's usage limit is used, as it last reported: its
/// fullest window, which routing goes by, and every window it reported.
class const Usage({
  required final double used,
  final DateTime? resetsAt,
  final DateTime? reportedAt,
  final List<UsageWindow> windows = const [],
}) {
  /// The fullest of [windows] as a whole Usage.
  static Usage? ofWindows(List<UsageWindow> windows) {
    if (windows.isEmpty) return null;
    final fullest = windows.reduce((a, b) => b.used > a.used ? b : a);
    return Usage(used: fullest.used, resetsAt: fullest.resetsAt, windows: windows);
  }

  Map<String, Object?> toJson() => {
    'used': used,
    'resetsAt': resetsAt?.toIso8601String(),
    'reportedAt': reportedAt?.toIso8601String(),
    if (windows.isNotEmpty) 'windows': [for (final w in windows) w.toJson()],
  };

  static Usage fromJson(Map<String, Object?> json) => Usage(
    used: (json['used']! as num).toDouble(),
    resetsAt: DateTime.tryParse('${json['resetsAt']}'),
    reportedAt: DateTime.tryParse('${json['reportedAt']}'),
    windows: [
      for (final w in (json['windows'] as List? ?? const []).whereType<Map>())
        UsageWindow.fromJson(w.cast()),
    ],
  );
}

/// A turn's tokens, as its connection reported them: input read fresh, read
/// from the provider's cache, written to it, and output. A figure the
/// connection does not report is null: unknown, never estimated.
class const TurnTokens({
  final int? fresh,
  final int? cacheRead,
  final int? cacheWrite,
  final int? output,
}) {
  Map<String, Object?> toJson() => {
    'fresh': fresh,
    'cacheRead': cacheRead,
    'cacheWrite': cacheWrite,
    'output': output,
  };
}
