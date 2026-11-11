/// Describes familiar work without exposing how it is carried out.
/// Unknown work stays generic. These labels never grant permission.
typedef ActivityWords = ({String action, String doing, String done, String group});

/// A short account of actual work, plus the labels in its expandable breakdown.
class ActivitySummary {
  const ActivitySummary(this.title, this.steps);
  final String title;
  final Map<String, String> steps;
}

ActivityWords commandActivity(String command) {
  final text = command.toLowerCase();
  final executableText = StringBuffer();
  String? quote;
  var escaped = false;
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (escaped) {
      executableText.write(' ');
      escaped = false;
      continue;
    }
    if (ch == '\\' && quote != "'") {
      executableText.write(' ');
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (ch == quote) quote = null;
      executableText.write(' ');
    } else if (ch == "'" || ch == '"') {
      quote = ch;
      executableText.write(' ');
    } else {
      executableText.write(ch);
    }
  }
  ActivityWords words(String action, String doing, String done, String group) =>
      (action: action, doing: doing, done: done, group: group);
  bool has(String pattern) => RegExp(
    '(?:^|[;&|\\n])\\s*(?:[\\w./-]+/)?(?:$pattern)',
    multiLine: true,
  ).hasMatch(executableText.toString());
  if (text.contains('helmy') &&
      (text.contains('relaunch') || text.contains('restart')) &&
      (text.contains('popen') || text.contains('nohup') || text.contains('write_text'))) {
    return words(
      'Prepare Helmy to reopen',
      'Preparing Helmy to reopen',
      'Prepared Helmy to reopen',
      'prepared a restart',
    );
  }
  if (has(r'\b(flutter test|dart test|npm test|pnpm test|pytest|cargo test|go test)\b')) {
    return words('Run tests', 'Running tests', 'Ran tests', 'ran tests');
  }
  if (has(r'\b(flutter analyze|dart analyze|ashlar check|npm run lint)\b')) {
    return words('Check the code', 'Checking the code', 'Checked the code', 'checked the code');
  }
  if (has(r'\b(flutter build|dart compile|npm run build|cargo build)\b')) {
    return words('Build the app', 'Building the app', 'Built the app', 'built the app');
  }
  if (has(r'\bashlar shot\b')) {
    return words(
      'Check the layout',
      'Checking the layout',
      'Checked the layout',
      'checked the layout',
    );
  }
  if (has(r'\b(dart format|prettier)\b')) {
    return words(
      'Format the code',
      'Formatting the code',
      'Formatted the code',
      'formatted the code',
    );
  }
  if (text.contains('helmy.app') && has(r'\b(ps|ls)\s')) {
    return words(
      'Check the installation',
      'Checking the installation',
      'Checked the installation',
      'checked the installation',
    );
  }
  if (has(r'\b(rg|grep|find)\s')) {
    return words(
      'Search the files',
      'Searching the files',
      'Searched the files',
      'searched the files',
    );
  }
  if (has(r'\bgit (status|diff|log)\b')) {
    return words(
      'Review the changes',
      'Reviewing the changes',
      'Reviewed the changes',
      'reviewed the changes',
    );
  }
  if (has(r'\b(ls|pwd|stat)\b')) {
    return words(
      'Inspect the folder',
      'Inspecting the folder',
      'Inspected the folder',
      'inspected the folder',
    );
  }
  if (has(r'\b(cat|sed|head|tail)\b')) {
    return words(
      'Read file contents',
      'Reading file contents',
      'Read file contents',
      'read file contents',
    );
  }
  return words('Run a script', 'Running a script', 'Ran a script', 'ran a script');
}

/// A factual label with the subject included, even when a generated account
/// is unavailable. Source text quoted in a reading command is not executed.
String specificCommandLabel(String command, {required bool done, String? result}) {
  final words = commandActivity(command);
  final paths = RegExp(
    r'(?:[\w.-]+/)*([\w.-]+)\.(?:dart|py|js|ts|tsx|jsx|swift|rs|go|java|kt|md|json|yaml)\b',
  ).allMatches(command).map((m) => m[1]!).toSet().take(3).toList();
  String friendly(String name) =>
      name.replaceAll(RegExp(r'(^test[_-]|[_-]test$)'), '').replaceAll(RegExp(r'[_-]'), ' ');
  final subjects = paths.map(friendly).toList();
  String join(List<String> parts) => parts.length < 2
      ? parts.join()
      : '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
  if (words.group == 'searched the files' || words.group == 'read file contents') {
    final concepts = <String>[
      if (RegExp(r'getLocalRectForCaret|line.?number', caseSensitive: false).hasMatch(command))
        'line-number alignment',
      if (RegExp(r'hasUnsavedEdits|_canLeave|onDirtyChanged').hasMatch(command))
        'unsaved-edit protection',
    ];
    if (concepts.isNotEmpty) return '${done ? 'Inspected' : 'Inspecting'} ${join(concepts)}';
    if (subjects.isNotEmpty) return '${done ? 'Inspected' : 'Inspecting'} ${join(subjects)}';
  }
  if (words.group == 'ran tests' && subjects.isNotEmpty) {
    final passed = done && (result ?? '').contains('All tests passed');
    final count = RegExp(r'\+(\d+)').allMatches(result ?? '').lastOrNull?.group(1);
    return passed
        ? 'Passed ${count == null ? '' : '$count '}checks for ${join(subjects)}'
        : '${done ? 'Tested' : 'Testing'} ${join(subjects)}';
  }
  return done ? words.done : words.doing;
}

/// Internal connections are not pages to show beside a conversation.
bool isInternalConnectionUrl(String address) {
  final uri = Uri.tryParse(address);
  if (uri == null || !{'localhost', '127.0.0.1', '0.0.0.0', '::1'}.contains(uri.host)) return false;
  if ({11434, 9222}.contains(uri.port)) return true;
  final path = uri.path.toLowerCase();
  return path == '/mcp' ||
      path.startsWith('/mcp/') ||
      path == '/sse' ||
      path.startsWith('/hooks/') ||
      path.startsWith('/devtools/');
}
