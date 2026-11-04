import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/utils/diff_rows.dart';

void main() {
  const lines = [
    '@@ -10,4 +10,5 @@',
    ' keep',
    '-old one',
    '-  spaced',
    '+new one',
    '+spaced',
    '+extra',
    ' end',
    '\\ No newline at end of file',
  ];

  test('side by side: removed beside what took its place, numbered from the hunk', () {
    final rows = sideBySide(lines);
    expect(
      [for (final r in rows) r.kind],
      [
        DiffKind.hunk,
        DiffKind.same,
        DiffKind.changed,
        DiffKind.changed,
        DiffKind.added,
        DiffKind.same, //
      ],
    );
    expect((rows[1].oldNo, rows[1].newNo), (10, 10));
    expect(
      (rows[2].oldNo, rows[2].oldText, rows[2].newNo, rows[2].newText),
      (11, 'old one', 11, 'new one'),
    );
    expect((rows[4].oldNo, rows[4].newNo, rows[4].newText), (null, 13, 'extra'));
    expect((rows[5].oldNo, rows[5].newNo), (13, 14));
  });

  test('changes only in spaces can read as the same', () {
    final rows = sideBySide(lines, hideSpace: true);
    expect(rows[3].kind, DiffKind.same);
    expect(rows[2].kind, DiffKind.changed);
  });

  test('one column: removed before added, numbers on each side', () {
    final rows = unified(lines);
    expect([for (final r in rows) '${r.kind.name}:${r.oldNo}:${r.newNo}'].take(5), [
      'hunk:null:null', 'same:10:10', 'removed:11:null', 'added:null:11', 'removed:12:null', //
    ]);
    expect(unified(lines, hideSpace: true).where((r) => r.text.contains('spaced')), hasLength(1));
  });

  test('no numbers where the diff does not give them', () {
    final rows = sideBySide(const [' a', '-b', '+c']);
    expect(rows.every((r) => r.oldNo == null && r.newNo == null), isTrue);
  });

  test('within a changed line, just what changed', () {
    final s = changedSpan('final x = 1;', 'final x = 42;');
    expect(
      ('final x = 1;'.substring(s.start, s.aEnd), 'final x = 42;'.substring(s.start, s.bEnd)),
      ('1', '42'),
    );
  });
}
