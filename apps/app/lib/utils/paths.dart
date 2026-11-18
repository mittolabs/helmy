import 'package:path/path.dart' as p;

/// Paths as every system writes them: a Mac and Linux with `/`, Windows
/// with `\` (and `/` too, which it accepts). A path the system hands over
/// (a folder's listing, a picked file, what an agent reports) is read with
/// these, never split on `/` alone.

/// The separators a path may have.
final _separator = RegExp(r'[/\\]');

/// The last part of [path]: a file's name or a folder's, with `/` or `\`
/// between its parts; [path] itself when it has none.
String baseName(String path) =>
    path.split(_separator).where((s) => s.isNotEmpty).lastOrNull ?? path;

/// The folder [path] is in, as written ('' when it names none): everything
/// before its last separator.
String parentOf(String path) {
  final trimmed = path.length > 1 ? path.replaceFirst(RegExp(r'[/\\]+$'), '') : path;
  final i = trimmed.lastIndexOf(_separator);
  if (i < 0) return '';
  return i == 0 ? trimmed.substring(0, 1) : trimmed.substring(0, i);
}

/// Whether [path] is a whole path on this system, not one relative to a
/// folder: `/Users/…`, or on Windows `C:\…`, `\\server\…`.
bool isAbsolutePath(String path, {p.Context? style}) =>
    (style ?? p.context).isAbsolute(path) || path.startsWith('/');

/// [path] in [folder]: [path] itself when it is already whole.
String inFolder(String folder, String path, {p.Context? style}) =>
    isAbsolutePath(path, style: style) ? path : (style ?? p.context).join(folder, path);

/// [path] with a leading `~` (`~/`, or `~\` on Windows) as [home].
String expandHome(String path, String home, {p.Context? style}) {
  if (path == '~') return home;
  if (path.startsWith('~/') || path.startsWith(r'~\')) {
    return (style ?? p.context).join(home, path.substring(2));
  }
  return path;
}

/// Whether [path] is [folder] or inside it, compared as this system
/// compares paths (on Windows, either separator and any case), and with
/// `..` worked out first, so `folder/../elsewhere` is not inside.
bool isInside(String path, String folder, {p.Context? style}) {
  final c = style ?? p.context;
  final a = c.normalize(c.absolute(path)), f = c.normalize(c.absolute(folder));
  return c.equals(a, f) || c.isWithin(f, a);
}

/// The name a program is known by, from its path: `git` for
/// `C:\Program Files\Git\bin\git.exe` or `/usr/bin/git`.
String programName(String path) =>
    baseName(path).replaceFirst(RegExp(r'\.(exe|cmd|bat|com)$', caseSensitive: false), '');

/// The words of a command typed in Settings, as a shell would split it:
/// "quoted words" and 'quoted words' stay whole, so a Windows program path
/// with spaces ("C:\Program Files\Agent\agent.exe" --acp) is one word. A
/// backslash is kept as it is: on Windows it separates folders.
List<String> commandWords(String line) {
  final words = <String>[];
  final word = StringBuffer();
  var inWord = false;
  String? quote;
  for (final ch in line.trim().split('')) {
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        word.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      inWord = true;
    } else if (ch.trim().isEmpty) {
      if (inWord) words.add(word.toString());
      word.clear();
      inWord = false;
    } else {
      word.write(ch);
      inWord = true;
    }
  }
  if (inWord) words.add(word.toString());
  return words;
}
