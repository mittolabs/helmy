import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/utils/starters.dart';

void main() {
  test('a repository with work in progress is offered a review of it', () {
    final s = startersFor((git: true, uncommitted: 3, recentCommits: 5));
    expect(s.map((s) => s.label), [
      'Review my uncommitted changes (3 files)',
      "Summarize this week's commits (5)",
      'Explain how this codebase is organized',
    ]);
  });

  test('nothing is suggested that is not true of the folder', () {
    final clean = startersFor((git: true, uncommitted: 0, recentCommits: 0));
    expect(clean.map((s) => s.label), ['Explain how this codebase is organized']);
    final plain = startersFor((git: false, uncommitted: 0, recentCommits: 0));
    expect(plain.map((s) => s.label), ['What is in this folder?']);
  });

  test('the facts are read from git', () async {
    final dir = await Directory.systemTemp.createTemp('starters');
    expect(await readFolderFacts(dir.path), (git: false, uncommitted: 0, recentCommits: 0));
    await Process.run('git', ['init', '-q'], workingDirectory: dir.path);
    File('${dir.path}/a.txt').writeAsStringSync('a');
    File('${dir.path}/b.txt').writeAsStringSync('b');
    final facts = await readFolderFacts(dir.path);
    expect(facts.git, isTrue);
    expect(facts.uncommitted, 2);
    expect(facts.recentCommits, 0);
    await dir.delete(recursive: true);
  });
}
