import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/snapshots.dart';

Future<void> git(String cwd, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
}

void main() {
  late Directory dir;
  late String cwd;
  final snapshots = Snapshots();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('snap');
    cwd = dir.path;
    await git(cwd, ['init', '-q']);
    await git(cwd, [
      '-c',
      'user.email=t@helmy.test',
      '-c',
      'user.name=t',
      'commit',
      '-q',
      '--allow-empty',
      '-m',
      'start',
    ]);
    File('$cwd/kept.txt').writeAsStringSync('one\ntwo\n');
    await git(cwd, ['add', 'kept.txt']);
    await git(cwd, [
      '-c',
      'user.email=t@helmy.test',
      '-c',
      'user.name=t',
      'commit',
      '-q',
      '-m',
      'kept',
    ]);
    // Work of yours from before the session: uncommitted, and must not count.
    File('$cwd/kept.txt').writeAsStringSync('one\ntwo\nyours\n');
    File('$cwd/draft.txt').writeAsStringSync('your draft\n');
  });
  tearDown(() => dir.delete(recursive: true));

  test('changes since a snapshot are only the ones made after it, by anything', () async {
    final before = (await snapshots.take(cwd))!;
    // As an agent's edit, a command and a new file would leave things.
    File('$cwd/kept.txt').writeAsStringSync('one\nTWO\nyours\n');
    File('$cwd/new.txt').writeAsStringSync('a\nb\n');
    final changes = await snapshots.changes(cwd, before);
    expect(changes.map((c) => c.path), ['kept.txt', 'new.txt']);
    expect(changes.first.kind, 'edited');
    expect((changes.first.added, changes.first.removed), (1, 1));
    expect(changes.last.kind, 'added');
    expect(await snapshots.diff(cwd, before, 'kept.txt'), contains('+TWO'));
    // The snapshot left everything as it was.
    expect(File('$cwd/draft.txt').readAsStringSync(), 'your draft\n');
    final stashes = await Process.run('git', ['stash', 'list'], workingDirectory: cwd);
    expect('${stashes.stdout}'.trim(), isEmpty);
  });

  test('restore puts files back as they were, your uncommitted work included', () async {
    final before = (await snapshots.take(cwd))!;
    File('$cwd/kept.txt').writeAsStringSync('ruined\n');
    File('$cwd/new.txt').writeAsStringSync('made by the agent\n');
    File('$cwd/draft.txt').deleteSync();
    await snapshots.restore(cwd, before, ['kept.txt', 'new.txt', 'draft.txt']);
    expect(File('$cwd/kept.txt').readAsStringSync(), 'one\ntwo\nyours\n');
    expect(File('$cwd/new.txt').existsSync(), isFalse);
    // An untracked file of yours comes back too, from the object kept for it.
    expect(File('$cwd/draft.txt').readAsStringSync(), 'your draft\n');
  });

  test('not a repository: no snapshot', () async {
    final plain = await Directory.systemTemp.createTemp('plain');
    expect(await snapshots.take(plain.path), isNull);
    await plain.delete(recursive: true);
  });
}
