/// A connection moves a session to another folder by ending its reply with a
/// line of its own, `HELMY_FOLDER: /the/full/path` (as the identity tells
/// it). The line is Helmy's, never the user's to see.
library;

const folderMarker = 'HELMY_FOLDER:';

final _line = RegExp(r'^[ \t]*HELMY_FOLDER:[ \t]*(\S[^\n]*?)[ \t]*$', multiLine: true);

/// The folder [text] moves to, the last one named; null when it names none.
String? folderMoveIn(String text) {
  final last = _line.allMatches(text).lastOrNull;
  return last?[1];
}

/// [text] without its folder lines. While [streaming], also without a last
/// line that may be one still arriving ("HELMY_FO"), so it never flashes.
String withoutFolderLines(String text, {bool streaming = false}) {
  var out = text.replaceAll(_line, '');
  if (streaming) {
    final cut = out.lastIndexOf('\n');
    final tail = out.substring(cut + 1).trim();
    if (tail.isNotEmpty && folderMarker.startsWith(tail)) out = out.substring(0, cut + 1);
  }
  return out.trimRight();
}
