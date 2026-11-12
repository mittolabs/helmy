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
  // Recording work comes before the look at it that often precedes it in the
  // same command: "git diff && git add && git commit" committed something.
  if (has(r'\bgit push\b')) {
    return words(
      'Push the changes',
      'Pushing the changes',
      'Pushed the changes',
      'pushed the changes',
    );
  }
  if (has(r'\bgit commit\b')) {
    return words(
      'Commit the changes',
      'Committing the changes',
      'Committed the changes',
      'committed the changes',
    );
  }
  if (has(r'\b(trash)\s')) {
    return words(
      'Move files to the Trash',
      'Moving files to the Trash',
      'Moved files to the Trash',
      'moved files to the trash',
    );
  }
  if (has(r'\bmkdir\s')) {
    return words('Create a folder', 'Creating a folder', 'Created a folder', 'created a folder');
  }
  if (has(r'\brm\s')) {
    return words('Remove files', 'Removing files', 'Removed files', 'removed files');
  }
  // Looking for particular files by name: "rg --files -g AGENTS.md", "find -name",
  // "[ -f AGENTS.md ]".
  if ((has(r'\brg\s+--files\b') && RegExp(r'''(?:-g|--glob)\s+['"]?[^!'"\s*]''').hasMatch(text)) ||
      has(r'\bfind\s[^;&|\n]*-i?name\b') ||
      RegExp(r'(?:\[|\btest)\s+-[fe]\s').hasMatch(executableText.toString())) {
    return words('Look for files', 'Looking for files', 'Looked for files', 'looked for files');
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
  // A program file run as it is ("node check-stripe.mjs"), not code written
  // into the command: named.
  final file = RegExp(
    r'^\s*(?:node|python3?|ruby|deno(?: run)?|bun|tsx|ts-node|bash|sh|zsh|swift|perl)\s+(?:[\w.~/-]+/)?([\w.-]+\.(?:mjs|cjs|js|ts|py|rb|sh|swift|pl))(?=\s|$)',
  ).firstMatch(command);
  if (file != null && !RegExp(r'[;&|]|<<|\s-[ce]\s').hasMatch(command)) {
    final name = file[1]!;
    return words('Run $name', 'Running $name', 'Ran $name', 'ran $name');
  }
  if (scriptActivity(text) case final w?) return w;
  return words('Run a script', 'Running a script', 'Ran a script', 'ran a script');
}

/// What an inline script does, read from its code: a script is the commonest
/// step an agent takes, and "Ran a script" says nothing to the person. Null when
/// the command is not a script, or does nothing recognized.
ActivityWords? scriptActivity(String command) {
  final text = command.toLowerCase();
  // Finder asked to delete a file puts it in the Trash.
  if (RegExp(r'finder.{0,8}to delete').hasMatch(text)) {
    return (
      action: 'Move files to the Trash',
      doing: 'Moving files to the Trash',
      done: 'Moved files to the Trash',
      group: 'moved files to the trash',
    );
  }
  final script = RegExp(
    r'\b(python3?|node|ruby|perl|osascript|deno|bun|swift)\b|\b(ba|z)?sh\s+-c\b|<<',
  ).hasMatch(text);
  if (!script) return null;
  bool has(String pattern) => RegExp(pattern).hasMatch(text);
  ActivityWords w(String action, String doing, String done, String group) =>
      (action: action, doing: doing, done: done, group: group);
  if (has(r'\bwhich\s|find_spec|command -v')) {
    return w(
      'Check the tools available',
      'Checking the tools available',
      'Checked the tools available',
      'checked the tools',
    );
  }
  final moves = has(r'shutil\.move|os\.rename|\.rename\(|fs\.rename|\bmv\s');
  final folders = has(r'makedirs|mkdir');
  if (has(r'\.trash\b|send2trash|trashitem|move.?to.?trash|to the trash')) {
    return w(
      'Move files to the Trash',
      'Moving files to the Trash',
      'Moved files to the Trash',
      'moved files to the trash',
    );
  }
  if (has(r'os\.remove|\bunlink\(|rmtree|fs\.rm|\brm\s+-')) {
    return w('Remove files', 'Removing files', 'Removed files', 'removed files');
  }
  if (moves && folders) {
    return w(
      'Sort files into folders',
      'Sorting files into folders',
      'Sorted files into folders',
      'sorted files',
    );
  }
  if (moves) return w('Move files', 'Moving files', 'Moved files', 'moved files');
  if (has(r'shutil\.copy|fs\.copyfile|\bcp\s')) {
    return w('Copy files', 'Copying files', 'Copied files', 'copied files');
  }
  if (has(r'filecmp|hashlib|\bmd5|sha\d|\bcmp\b|difflib|\bdiff\b')) {
    return w('Compare files', 'Comparing files', 'Compared files', 'compared files');
  }
  if (has(r'pdftotext|pypdf|pdfminer|pdfkit|\bmdls\b|textutil')) {
    return w(
      'Read the documents',
      'Reading the documents',
      'Read the documents',
      'read the documents',
    );
  }
  if (has(r'read_text|readfilesync|\.read\(') &&
      has(r'write_text|writefile') &&
      has(r'\.replace\(')) {
    return w('Edit a file', 'Editing a file', 'Edited a file', 'edited a file');
  }
  if (has(r'write_text|writefile|open\([^)]*,\s*.w')) {
    return w('Write a file', 'Writing a file', 'Wrote a file', 'wrote a file');
  }
  if (folders) return w('Create folders', 'Creating folders', 'Created folders', 'created folders');
  if (has(r'\bpil\b|from pil|\bsips\b|\bmagick\b')) {
    return w(
      'Process the images',
      'Processing the images',
      'Processed the images',
      'processed images',
    );
  }
  if (has(r'requests\.|urllib|fetch\(|\bcurl\b')) {
    return w(
      'Fetch from the web',
      'Fetching from the web',
      'Fetched from the web',
      'fetched from the web',
    );
  }
  if (has(r'csv\.|json\.load|pandas|readfile|read_text|\.read\(')) {
    return w('Read the files', 'Reading the files', 'Read the files', 'read the files');
  }
  if (has(r'listdir|iterdir|scandir|glob\(|readdir|os\.walk')) {
    return w(
      'Look through the folder',
      'Looking through the folder',
      'Looked through the folder',
      'inspected the folder',
    );
  }
  return null;
}

/// Files a command names, as a person would: "lease-draft-v3.txt", not its path.
/// Only quoted names with an extension people know count, so code (f.name,
/// *.pdf, importlib.util) is never mistaken for a file.
List<String> namedFiles(String command) => {
  // Escaped quotes (a script inside a shell command) are quotes too.
  for (final m in RegExp(
    r'''(['"])([^'"\n]*?\.([A-Za-z0-9]{2,5}))\1''',
  ).allMatches(command.replaceAll(r'\"', '"')))
    if (_fileExtensions.contains(m[3]!.toLowerCase()) && !m[2]!.contains('*'))
      m[2]!.split('/').last,
}.where((n) => n.isNotEmpty && !n.startsWith('.')).take(5).toList();

/// What a step turned down before it ran would have done, from its title in
/// the past tense: "Removed notes.md" is "Didn't remove notes.md". A verb not
/// known here keeps the title whole, after "Didn't go ahead:".
String declinedLabel(String doneTitle) {
  final space = doneTitle.indexOf(' ');
  final verb = space < 0 ? doneTitle : doneTitle.substring(0, space);
  final rest = space < 0 ? '' : doneTitle.substring(space);
  if (_baseOf[verb] case final base?) return "Didn't $base$rest";
  final lower = doneTitle.isEmpty ? doneTitle : doneTitle[0].toLowerCase() + doneTitle.substring(1);
  return "Didn't go ahead: $lower";
}

const _baseOf = {
  'Removed': 'remove',
  'Moved': 'move',
  'Copied': 'copy',
  'Compared': 'compare',
  'Read': 'read',
  'Looked': 'look',
  'Committed': 'commit',
  'Pushed': 'push',
  'Ran': 'run',
  'Checked': 'check',
  'Built': 'build',
  'Formatted': 'format',
  'Inspected': 'inspect',
  'Searched': 'search',
  'Reviewed': 'review',
  'Sorted': 'sort',
  'Created': 'create',
  'Wrote': 'write',
  'Processed': 'process',
  'Fetched': 'fetch',
  'Tested': 'test',
  'Edited': 'edit',
  'Used': 'use',
  'Asked': 'ask',
  'Updated': 'update',
  'Made': 'make',
  'Prepared': 'prepare',
  'Listed': 'list',
  'Deleted': 'delete',
  'Sent': 'send',
  'Opened': 'open',
  'Installed': 'install',
  'Started': 'start',
  'Stopped': 'stop',
};

/// Files a plain shell command names without quotes (rm a/b/notes.md), by
/// name, each once.
List<String> _bareFiles(String command) => {
  for (final m in RegExp(
    r'(?:^|\s)/?(?:[\w~.@+-]+/)*([\w@+-][\w.@+-]*?\.([A-Za-z0-9]{2,5}))(?=[\s;&|)]|$)',
  ).allMatches(command))
    if (_fileExtensions.contains(m[2]!.toLowerCase())) m[1]!,
}.take(5).toList();

const _fileExtensions = {
  'txt',
  'md',
  'pdf',
  'doc',
  'docx',
  'rtf',
  'pages',
  'csv',
  'tsv',
  'xls',
  'xlsx',
  'numbers',
  'ppt',
  'pptx',
  'key',
  'json',
  'yaml',
  'yml',
  'xml',
  'html',
  'css',
  'log',
  'png',
  'jpg',
  'jpeg',
  'heic',
  'gif',
  'webp',
  'svg',
  'tiff',
  'mp3',
  'm4a',
  'wav',
  'mp4',
  'mov',
  'zip',
  'dmg',
  'pkg',
  'tar',
  'gz',
  'py',
  'js',
  'ts',
  'dart',
  'swift',
  'go',
  'rs',
  'sh',
};

/// A step Codex parsed into actions (a file read, a folder listed, a search),
/// in words. Null when there is nothing but unknown actions.
String? actionsLabel(List<Object?> actions, {required bool done}) {
  final words = <String>[];
  for (final a in actions.whereType<Map>()) {
    final name = '${a['name'] ?? ''}'.split('/').last;
    final path = '${a['path'] ?? ''}'.split('/').where((p) => p.isNotEmpty).lastOrNull;
    final query = '${a['query'] ?? ''}';
    final w = switch (a['type']) {
      'read' when name.isNotEmpty => '${done ? 'Read' : 'Reading'} $name',
      'listFiles' => '${done ? 'Listed' : 'Listing'} ${path ?? 'the folder'}',
      'search' when query.isNotEmpty => '${done ? 'Searched for' : 'Searching for'} "$query"',
      'search' => done ? 'Searched the files' : 'Searching the files',
      _ => null,
    };
    if (w != null && !words.contains(w)) words.add(w);
  }
  if (words.isEmpty) return null;
  String lower(String s) => s[0].toLowerCase() + s.substring(1);
  if (words.length == 1) return words.single;
  if (words.length == 2) return '${words[0]} and ${lower(words[1])}';
  return '${words[0]}, ${lower(words[1])} and more';
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
  const filesGroups = {
    'moved files to the trash': ('Moving', 'Moved', ' to the Trash'),
    'removed files': ('Removing', 'Removed', ''),
    'moved files': ('Moving', 'Moved', ''),
    'copied files': ('Copying', 'Copied', ''),
    'compared files': ('Comparing', 'Compared', ''),
    'read the documents': ('Reading', 'Read', ''),
    'edited a file': ('Editing', 'Edited', ''),
    'wrote a file': ('Writing', 'Wrote', ''),
  };
  if (filesGroups[words.group] case (final doing, final did, final tail)) {
    // A script names the files it reads too: a file written is named only when it is
    // the only one.
    final most = words.group == 'wrote a file' || words.group == 'edited a file' ? 1 : 2;
    final named = namedFiles(command);
    if (named.isNotEmpty && named.length <= most) {
      return '${done ? did : doing} ${join(named)}$tail';
    }
    // A plain command (rm, mv) names its files unquoted.
    final bare = scriptActivity(command) == null ? _bareFiles(command) : const <String>[];
    if (bare.isNotEmpty && bare.length <= most) return '${done ? did : doing} ${join(bare)}$tail';
  }
  if (words.group == 'looked for files') {
    // The names looked for, not patterns ("*menu*").
    final names = {
      for (final m in RegExp(r'''(?:-g|-i?name)\s+(['"]?)([^'"\s]+)\1''').allMatches(command))
        if (!m[2]!.contains('*') && !m[2]!.startsWith('!')) m[2]!.split('/').last,
      ...namedFiles(command),
      ..._bareFiles(command),
    }.toList();
    if (names.isNotEmpty && names.length <= 3) {
      return '${done ? 'Looked for' : 'Looking for'} ${join(names)}';
    }
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
