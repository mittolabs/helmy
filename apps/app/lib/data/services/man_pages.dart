import 'dart:io';

import '../../ui/chat/widgets/step_input.dart' show ShellPart, shellParts;

/// One piece of a command, explained from the Mac's own manual: a program and
/// what it is, or one of its flags and what it does. [help] is null when the
/// manual does not say.
typedef ManPart = ({String text, String? help, bool program});

/// Explains [command] from manual pages alone: free, offline, and only as
/// good as the pages. Arguments other than flags are left out.
Future<List<ManPart>> explainFromManual(String command) async {
  final out = <ManPart>[];
  String? page;
  final pages = <String, String?>{};
  var programs = 0;
  final parts = [
    for (final p in shellParts(command))
      if (p.$1 != ShellPart.space) p,
  ];
  for (var i = 0; i < parts.length; i++) {
    final (kind, text) = parts[i];
    if (kind == ShellPart.program) {
      if (++programs > 8) break;
      var name = text.split('/').last;
      // "git log" has a page of its own, git-log.
      if (i + 1 < parts.length && parts[i + 1].$1 == ShellPart.word) {
        final sub = '$name-${parts[i + 1].$2}';
        if ((pages[sub] ??= await manText(sub)) != null) {
          name = '$name ${parts[i + 1].$2}';
          page = pages[sub];
          out.add((text: name, help: nameLine(page!), program: true));
          i++;
          continue;
        }
      }
      page = pages[name] ??= await manText(name);
      out.add((
        text: name,
        help: _builtins[name] ?? (page == null ? null : nameLine(page)),
        program: true,
      ));
    } else if (kind == ShellPart.flag && page != null) {
      final help = flagHelp(page, text);
      if (help != null || !RegExp(r'^-[a-zA-Z]{2,}$').hasMatch(text)) {
        out.add((text: text, help: help, program: false));
      } else {
        // "-la" is "-l" and "-a" together.
        for (final letter in text.substring(1).split('')) {
          out.add((text: '-$letter', help: flagHelp(page, '-$letter'), program: false));
        }
      }
    }
  }
  return out;
}

/// Shell built-ins, which have no page of their own.
const _builtins = {
  'cd': 'change the working directory',
  'export': 'set an environment variable for the commands that follow',
  'source': 'run the commands in a file in the current shell',
  '.': 'run the commands in a file in the current shell',
  'alias': 'define a short name for a command',
  'set': 'set shell options',
  'unset': 'remove a variable',
  'pushd': 'change directory, remembering the one left',
  'popd': 'go back to the directory pushd left',
  'exit': 'leave the shell',
};

/// The plain text of [program]'s manual page; null when it has none.
Future<String?> manText(String program) async {
  if (!RegExp(r'^[\w.+-]+$').hasMatch(program)) return null;
  try {
    final r = await Process.run(
      '/usr/bin/man',
      ['-P', 'cat', program],
      environment: {'MANWIDTH': '100', 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'},
    );
    if (r.exitCode != 0) return null;
    final text = plainMan('${r.stdout}');
    return text.trim().isEmpty ? null : text;
  } on Object {
    return null;
  }
}

/// A manual page's text with its overstrike (bold and underline) taken out.
String plainMan(String raw) => raw.replaceAll(RegExp('.\x08'), '');

/// What the NAME section says the program is: "list directory contents".
String? nameLine(String man) {
  final lines = man.split('\n');
  final i = lines.indexWhere((l) => l.trim() == 'NAME');
  if (i < 0) return null;
  // The section runs to the next blank line; long lists of names wrap.
  final section = lines
      .skip(i + 1)
      .skipWhile((l) => l.trim().isEmpty)
      .takeWhile((l) => l.trim().isNotEmpty)
      .map((l) => l.trim())
      .join(' ');
  final m = RegExp(r'\s[–—-]\s+(.+)$').firstMatch(section);
  return m == null ? null : m[1]!.trim();
}

/// What the manual says [flag] does: the paragraph under its entry in the
/// options list, cut to about two sentences.
String? flagHelp(String man, String flag) {
  final lines = man.split('\n');
  final entry = RegExp(
    r'^(\s+)(?:-[\w-]+(?:[ =]\S+)?,\s*)*' + RegExp.escape(flag) + r'(?![\w-])(.*)$',
  );
  for (var i = 0; i < lines.length; i++) {
    final m = entry.firstMatch(lines[i]);
    if (m == null || m[1]!.length > 16) continue;
    final indent = m[1]!.length;
    // On the same line: an argument name, then the description after a gap.
    final rest = m[2]!;
    final gap = RegExp(r'\s{2,}(.+)$').firstMatch(rest);
    final words = <String>[if (gap != null) gap[1]!.trim()];
    for (var j = i + 1; j < lines.length; j++) {
      final l = lines[j];
      if (l.trim().isEmpty) break;
      final lead = l.length - l.trimLeft().length;
      if (lead <= indent) break;
      words.add(l.trim());
    }
    final text = words.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    return _twoSentences(text);
  }
  return null;
}

String _twoSentences(String text) {
  final ends = RegExp(r'[.!?](\s|$)').allMatches(text).toList();
  final cut = ends.length >= 2 ? ends[1].end : text.length;
  final s = text.substring(0, cut).trim();
  return s.length > 280 ? '${s.substring(0, 277)}...' : s;
}
