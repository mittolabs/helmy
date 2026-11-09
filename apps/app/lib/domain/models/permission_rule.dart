import 'chat_item.dart';
import '../../utils/format.dart';

/// What a rule allows without asking: commands that start a certain way, or
/// edits under a folder. Kept in settings, so it lasts.
class const PermissionRule({required final String kind, required final String prefix}) {
  Map<String, Object?> toJson() => {'kind': kind, 'prefix': prefix};

  static PermissionRule fromJson(Map<String, Object?> json) =>
      PermissionRule(kind: '${json['kind']}', prefix: '${json['prefix']}');

  String get label => switch (kind) {
    'command' => 'Commands starting "${prefix.trim()}"',
    // The folder as the user reads it: one with no project is the chat's own.
    'edit' => isScratch(prefix) ? "Edits in this chat's folder" : 'Edits in ${tildePath(prefix)}',
    _ => '$kind: $prefix',
  };

  /// The rule a prompt would make if always allowed: its command's first word,
  /// or the folder of the session. Null when a prompt is not one a rule covers.
  static PermissionRule? from(PermissionPrompt p, String cwd) => switch (kindOf(p.toolName)) {
    'command' => switch (plainCommand('${p.input['command'] ?? ''}').split(RegExp(r'\s+'))) {
      [final word, ...] when word.isNotEmpty => PermissionRule(kind: 'command', prefix: '$word '),
      _ => null,
    },
    'edit' => PermissionRule(kind: 'edit', prefix: cwd),
    _ => null,
  };

  bool allows(PermissionPrompt p) => switch (kindOf(p.toolName)) {
    'command' when kind == 'command' =>
      '${plainCommand('${p.input['command'] ?? ''}')} '.startsWith(prefix),
    'edit' when kind == 'edit' =>
      '${p.input['file_path'] ?? p.input['grantRoot'] ?? ''}'.startsWith(prefix) ||
          p.input['file_path'] == null && p.input['grantRoot'] == null,
    _ => false,
  };

  static String? kindOf(String tool) => switch (tool) {
    'Bash' || 'Shell' => 'command',
    'Write' || 'Edit' || 'NotebookEdit' => 'edit',
    _ => null,
  };

  /// Codex wraps a command in its shell: `/bin/zsh -lc "git status"`. The
  /// rule is about `git status`.
  static String plainCommand(String command) {
    final m = RegExp(
      r'''^\S*/(?:z|ba)?sh\s+-l?c\s+(['"])(.*)\1\s*$''',
      dotAll: true,
    ).firstMatch(command.trim());
    return (m?.group(2) ?? command).trim();
  }
}
