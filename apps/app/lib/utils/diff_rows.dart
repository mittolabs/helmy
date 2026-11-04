/// What a row of a diff shows.
enum DiffKind {
  /// The same before and after.
  same,

  /// Only after.
  added,

  /// Only before.
  removed,

  /// A line changed: before beside after.
  changed,

  /// Where a part of the file starts (git's "@@ -12,4 +12,6 @@").
  hunk,
}

/// One row of a diff side by side: the line before (left) and after (right),
/// with their numbers in the file when the diff says them.
typedef SideRow = ({DiffKind kind, int? oldNo, String? oldText, int? newNo, String? newText});

/// One row of a diff in one column, with its numbers before and after.
typedef UniRow = ({DiffKind kind, int? oldNo, int? newNo, String text});

final _hunk = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');

/// The same text but for its spaces and tabs.
bool sameButSpace(String a, String b) =>
    a.replaceAll(RegExp(r'\s+'), '') == b.replaceAll(RegExp(r'\s+'), '');

/// [lines] (unified: ' ' same, '+' added, '-' removed, '@@' hunk) side by
/// side: removed lines paired with the added ones that took their place.
/// With [hideSpace], a pair that differs only in spaces reads as the same.
/// Numbers only where the diff gives them (it has @@ headers).
List<SideRow> sideBySide(List<String> lines, {bool hideSpace = false}) {
  final out = <SideRow>[];
  final numbered = lines.any(_hunk.hasMatch);
  var oldNo = 1, newNo = 1;
  final removed = <String>[], added = <String>[];
  void flush() {
    final n = removed.length > added.length ? removed.length : added.length;
    for (var i = 0; i < n; i++) {
      final o = i < removed.length ? removed[i] : null;
      final a = i < added.length ? added[i] : null;
      final kind = o != null && a != null
          ? (hideSpace && sameButSpace(o, a) ? DiffKind.same : DiffKind.changed)
          : o != null
          ? DiffKind.removed
          : DiffKind.added;
      out.add((
        kind: kind,
        oldNo: o == null || !numbered ? null : oldNo,
        oldText: o,
        newNo: a == null || !numbered ? null : newNo,
        newText: a,
      ));
      if (o != null) oldNo++;
      if (a != null) newNo++;
    }
    removed.clear();
    added.clear();
  }

  for (final l in lines) {
    if (l.startsWith('\\')) continue; // "\ No newline at end of file"
    final h = _hunk.firstMatch(l);
    if (h != null) {
      flush();
      oldNo = int.parse(h[1]!);
      newNo = int.parse(h[2]!);
      out.add((kind: DiffKind.hunk, oldNo: null, oldText: l, newNo: null, newText: l));
    } else if (l.startsWith('-')) {
      removed.add(l.substring(1));
    } else if (l.startsWith('+')) {
      added.add(l.substring(1));
    } else {
      flush();
      final text = l.isEmpty ? '' : l.substring(1);
      out.add((
        kind: DiffKind.same,
        oldNo: numbered ? oldNo : null,
        oldText: text,
        newNo: numbered ? newNo : null,
        newText: text,
      ));
      oldNo++;
      newNo++;
    }
  }
  flush();
  return out;
}

/// [lines] in one column, removed before added; with [hideSpace], a removed
/// and added pair that differs only in spaces shows once, as the same.
List<UniRow> unified(List<String> lines, {bool hideSpace = false}) => [
  for (final r in sideBySide(lines, hideSpace: hideSpace))
    ...switch (r.kind) {
      .hunk => [(kind: DiffKind.hunk, oldNo: null, newNo: null, text: r.oldText!)],
      .same => [(kind: DiffKind.same, oldNo: r.oldNo, newNo: r.newNo, text: r.newText!)],
      .added => [(kind: DiffKind.added, oldNo: null, newNo: r.newNo, text: r.newText!)],
      .removed => [(kind: DiffKind.removed, oldNo: r.oldNo, newNo: null, text: r.oldText!)],
      .changed => [
        (kind: DiffKind.removed, oldNo: r.oldNo, newNo: null, text: r.oldText!),
        (kind: DiffKind.added, oldNo: null, newNo: r.newNo, text: r.newText!),
      ],
    },
];

/// Where [a] and [b] differ: the start and end of the changed middle in each,
/// once their shared start and end are set aside. For marking, within a
/// changed line, just what changed.
({int start, int aEnd, int bEnd}) changedSpan(String a, String b) {
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var aEnd = a.length, bEnd = b.length;
  while (aEnd > start && bEnd > start && a[aEnd - 1] == b[bEnd - 1]) {
    aEnd--;
    bEnd--;
  }
  return (start: start, aEnd: aEnd, bEnd: bEnd);
}
