import '../domain/models/chat_item.dart';

/// One file's change as unified-diff lines: ' ' kept, '+' added, '-' removed.
typedef FileDiff = ({String path, List<String> lines, int added, int removed});

/// The changes a step made or wants to make, from what each engine sends:
/// Claude's Edit gives the old and new text, its Write the whole new file, and
/// Codex a unified diff per file. Empty for steps that change no file.
List<FileDiff> diffsOf(ToolCall call) {
  final input = call.input;
  switch (call.name) {
    case 'Edit' when input['old_string'] is String:
      return [
        _diff(
          '${input['file_path']}',
          input['old_string']! as String,
          '${input['new_string'] ?? ''}',
        ),
      ];
    case 'Write' when input['content'] is String:
      return [_diff('${input['file_path']}', '', input['content']! as String)];
    case 'Edit' when input['changes'] is List:
      return [
        for (final c in (input['changes']! as List).whereType<Map>())
          _fromUnified('${c['path']}', '${c['diff'] ?? ''}'),
      ];
  }
  return const [];
}

/// A unified diff of one file, as [FileDiff].
FileDiff parseUnified(String path, String diff) => _fromUnified(path, diff);

FileDiff _fromUnified(String path, String diff) {
  final lines = [
    for (final l in diff.split('\n'))
      if (!l.startsWith('+++') &&
          !l.startsWith('---') &&
          !l.startsWith('diff ') &&
          !l.startsWith('index '))
        l,
  ];
  return (
    path: path,
    lines: lines,
    added: lines.where((l) => l.startsWith('+')).length,
    removed: lines.where((l) => l.startsWith('-')).length,
  );
}

/// A line diff of [before] and [after], by their longest common run of lines.
FileDiff _diff(String path, String before, String after) {
  final a = before.isEmpty ? <String>[] : before.split('\n');
  final b = after.isEmpty ? <String>[] : after.split('\n');
  // Edits are small; past this size a plain "all removed, all added" is fine.
  if (a.length * b.length > 250000) {
    final lines = [for (final l in a) '-$l', for (final l in b) '+$l'];
    return (path: path, lines: lines, added: b.length, removed: a.length);
  }
  final m = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      m[i][j] = a[i] == b[j]
          ? m[i + 1][j + 1] + 1
          : (m[i + 1][j] > m[i][j + 1] ? m[i + 1][j] : m[i][j + 1]);
    }
  }
  final lines = <String>[];
  var i = 0, j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      lines.add(' ${a[i]}');
      i++;
      j++;
    } else if (i < a.length && (j == b.length || m[i + 1][j] >= m[i][j + 1])) {
      // Removed before added, as diffs are read.
      lines.add('-${a[i++]}');
    } else {
      lines.add('+${b[j++]}');
    }
  }
  return (
    path: path,
    lines: lines,
    added: lines.where((l) => l.startsWith('+')).length,
    removed: lines.where((l) => l.startsWith('-')).length,
  );
}
