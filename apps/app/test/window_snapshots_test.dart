import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/window_snapshots.dart';

void main() {
  const w = (id: 1, pid: 2, app: 'Helmy', title: 'Helmy');

  test("a window's text is kept only when it says more than the window's name", () {
    expect(WindowSnapshots.saysMore('- Window: Helmy\n  - Group: Helmy', w), isFalse);
    expect(
      WindowSnapshots.saysMore(
        '- Window: Notes\n  - TextArea: Buy milk\n  - Button: Share\n  - StaticText: 3 notes',
        (id: 1, pid: 2, app: 'Notes', title: 'Notes'),
      ),
      isTrue,
    );
  });

  test('a file name from the app and title, safe on disk and not too long', () {
    expect(
      WindowSnapshots.nameFor((id: 1, pid: 2, app: 'Safari', title: 'a/b: c?')),
      'Safari, a-b- c-',
    );
    expect(WindowSnapshots.nameFor((id: 1, pid: 2, app: 'Finder', title: '')), 'Finder');
    expect(WindowSnapshots.nameFor((id: 1, pid: 2, app: 'X', title: 'y' * 200)).length, 80);
  });

  test("the text file names its window and says what it holds", () {
    final text = WindowSnapshots.textOf((
      id: 1,
      pid: 2,
      app: 'Notes',
      title: 'Groceries',
    ), '- TextArea: Buy milk');
    expect(text, startsWith('# Notes: Groceries'));
    expect(text, contains('- TextArea: Buy milk'));
  });
}
