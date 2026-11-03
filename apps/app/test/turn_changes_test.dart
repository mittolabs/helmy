import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/snapshots.dart';

void main() {
  test("each turn's changes are its own work, tracked files and new ones alike", () async {
    final dir = await Directory.systemTemp.createTemp('turns');
    Future<void> git(List<String> a) => Process.run('git', a, workingDirectory: dir.path);
    await git(['init', '-q']);
    await git(['config', 'user.email', 'test@helmy.test']);
    await git(['config', 'user.name', 'Test']);
    File('${dir.path}/a.txt').writeAsStringSync('one\ntwo\n');
    File('${dir.path}/b.txt').writeAsStringSync('bee\n');
    await git(['add', '.']);
    await git(['commit', '-qm', 'start']);
    final snaps = Snapshots();

    // Turn 1: edits a.txt and adds a new, untracked notes.md.
    final before1 = (await snaps.take(dir.path))!;
    File('${dir.path}/a.txt').writeAsStringSync('one\nTWO\n');
    File('${dir.path}/notes.md').writeAsStringSync('# Notes\nfirst\n');

    // Turn 2: edits b.txt and the untracked notes.md.
    final before2 = (await snaps.take(dir.path))!;
    File('${dir.path}/b.txt').writeAsStringSync('bee\nsea\n');
    File('${dir.path}/notes.md').writeAsStringSync('# Notes\nfirst\nsecond\n');

    // Turn 3 (the latest): removes a.txt.
    final before3 = (await snaps.take(dir.path))!;
    File('${dir.path}/a.txt').deleteSync();

    String show(List<FileChange> cs) =>
        [for (final c in cs) '${c.path} ${c.kind} +${c.added} -${c.removed}'].join(', ');

    expect(
      show(await snaps.changesBetween(dir.path, before1, before2)),
      'a.txt edited +1 -1, notes.md added +2 -0',
    );
    expect(
      show(await snaps.changesBetween(dir.path, before2, before3)),
      'b.txt edited +1 -0, notes.md edited +1 -0',
    );
    // The latest turn runs up to now.
    expect(show(await snaps.changes(dir.path, before3)), 'a.txt removed +0 -2');

    final diff = await snaps.diffBetween(dir.path, before2, before3, 'notes.md');
    expect(diff, contains('+second'));
    expect(diff, isNot(contains('+first')));
    final added = await snaps.diffBetween(dir.path, before1, before2, 'notes.md');
    expect(added, contains('+# Notes'));
    await dir.delete(recursive: true);
  });
}
