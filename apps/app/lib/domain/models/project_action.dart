/// A command a project is worked with (run it, test it, build it), run in a
/// terminal beside the conversation. Found in the project's own files
/// ([from] says which), or added by the user ([from] null).
class const ProjectAction({
  required final String name,
  required final String command,

  /// Run in each new copy of the project made for a session (install the
  /// dependencies, say), before anything else there.
  final bool onNewCopy = false,

  /// The file it was found in (package.json, Makefile); null for one the
  /// user added.
  final String? from,
}) {
  bool get own => from == null;

  /// The same action, identified by what it runs.
  String get key => '$name\u0000$command';

  ProjectAction copyWith({String? name, String? command, bool? onNewCopy}) => ProjectAction(
    name: name ?? this.name,
    command: command ?? this.command,
    onNewCopy: onNewCopy ?? this.onNewCopy,
    from: from,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'command': command,
    if (onNewCopy) 'onNewCopy': true,
  };

  static ProjectAction fromJson(Map<String, Object?> json) => ProjectAction(
    name: json['name'] as String? ?? '',
    command: json['command'] as String? ?? '',
    onNewCopy: json['onNewCopy'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is ProjectAction &&
      other.name == name &&
      other.command == command &&
      other.onNewCopy == onNewCopy &&
      other.from == from;

  @override
  int get hashCode => Object.hash(name, command, onNewCopy, from);
}
