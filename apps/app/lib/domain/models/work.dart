/// The kinds of work a message can be, for sending it to the connection
/// best at that kind (Settings > Connections > Advanced).
enum WorkKind {
  code('Code', 'Changing, fixing and explaining code'),
  writing('Writing', 'Drafts, emails, posts, rewrites'),
  research('Research', 'Looking things up and reading'),
  pictures('Pictures', 'Making and changing images'),
  accounts('Your accounts', 'Drive, Gmail, Calendar, Slack, Notion'),
  quick('Quick questions', 'A short question with a short answer');

  const WorkKind(this.label, this.description);
  final String label;
  final String description;
}

/// Mittolabs's choice of which connection (by kind: every Claude Code
/// account is 'claude') is best at each kind of work; null is any, by room.
/// Our judgment, not a measurement: no neutral comparison of the agents on
/// these kinds exists (docs/notes/helmy-providers.md).
const Map<WorkKind, String?> defaultBestAt = {
  WorkKind.code: 'claude',
  WorkKind.writing: 'claude',
  WorkKind.research: null,
  WorkKind.pictures: 'codex',
  WorkKind.accounts: 'claude',
  WorkKind.quick: null,
};
