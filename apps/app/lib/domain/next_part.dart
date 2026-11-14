/// Long work in parts. A connection ends a part of a long piece of work with
/// a last paragraph of its own, `HELMY_NEXT: where things stand and what the
/// next part is` (as the identity tells it). Helmy then starts the next part
/// from that note in a fresh context, so each step of the next part reads a
/// short conversation instead of everything before it: long work stays quick
/// and uses far less of the person's plan. The note leaves the answer and
/// opens the next part's message instead.
library;

const nextMarker = 'HELMY_NEXT:';

/// Where a next part's message came from, as it says. It carries the
/// agent's own note, so it never counts as the person asking for anything.
const nextPartFrom = 'Helmy, starting the next part';

final _start = RegExp(r'^[ \t]*HELMY_NEXT:', multiLine: true);

/// The note [text] ends a part with, everything after the last marker;
/// null when it ends none, or the note is empty.
String? nextPartIn(String text) {
  final at = _start.allMatches(text).lastOrNull;
  if (at == null) return null;
  final note = text.substring(at.end).trim();
  return note.isEmpty ? null : note;
}

/// [text] without its next-part note. While [streaming], also without a
/// last line that may be the marker still arriving ("HELMY_N"), so it never
/// flashes.
String withoutNextPart(String text, {bool streaming = false}) {
  var out = text;
  final at = _start.firstMatch(out);
  if (at != null) out = out.substring(0, at.start);
  if (streaming) {
    final cut = out.lastIndexOf('\n');
    final tail = out.substring(cut + 1).trim();
    if (tail.isNotEmpty && nextMarker.startsWith(tail)) out = out.substring(0, cut + 1);
  }
  return out.trimRight();
}
