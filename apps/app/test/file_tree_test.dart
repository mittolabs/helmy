import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/utils/file_tree.dart';

void main() {
  const files = [
    'README.md',
    'lib/main.dart',
    'lib/ui/app.dart',
    'lib/ui/Button.dart',
    'apps/app/lib/main.dart',
    'apps/app/pubspec.yaml',
    'Makefile',
  ];

  String show(List<FileRow> rows) =>
      [for (final r in rows) '${'  ' * r.depth}${r.name}${r.folder ? (r.open ? '/ v' : '/') : ''}']
          .join('\n');

  test('folders first, then files, by name with case aside', () {
    expect(show(visibleRows(files, {})), 'apps/app/\nlib/\nMakefile\nREADME.md');
  });

  test('a folder holding only a folder joins it, as editors show it', () {
    final rows = visibleRows(files, {'apps/app'});
    expect(show(rows), 'apps/app/ v\n  lib/\n  pubspec.yaml\nlib/\nMakefile\nREADME.md');
    expect(rows.first.path, 'apps/app', reason: 'opened by the deepest folder it stands for');
  });

  test('open folders show what they hold, nested', () {
    expect(
      show(visibleRows(files, {'lib', 'lib/ui'})),
      'apps/app/\nlib/ v\n  ui/ v\n    app.dart\n    Button.dart\n  main.dart\nMakefile\nREADME.md',
    );
  });

  test("a file's folders, to open so it shows", () {
    expect(foldersOf('apps/app/lib/main.dart').toList(), ['apps', 'apps/app', 'apps/app/lib']);
    expect(foldersOf('README.md'), isEmpty);
  });

  test("a file's language, from its name", () {
    expect(languageOf('main.dart'), 'dart');
    expect(languageOf('App.TSX'), 'typescript');
    expect(languageOf('Makefile'), 'makefile');
    expect(languageOf('Info.plist'), 'xml');
    expect(languageOf('notes'), isNull);
    expect(languageOf('photo.png'), isNull);
  });
}
