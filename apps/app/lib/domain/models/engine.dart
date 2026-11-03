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

/// How much of an engine's usage limit is used, as it last reported.
class const Usage({
  required final double used,
  final DateTime? resetsAt,
  final DateTime? reportedAt,
}) {
  Map<String, Object?> toJson() => {
    'used': used,
    'resetsAt': resetsAt?.toIso8601String(),
    'reportedAt': reportedAt?.toIso8601String(),
  };

  static Usage fromJson(Map<String, Object?> json) => Usage(
    used: (json['used']! as num).toDouble(),
    resetsAt: DateTime.tryParse('${json['resetsAt']}'),
    reportedAt: DateTime.tryParse('${json['reportedAt']}'),
  );
}
