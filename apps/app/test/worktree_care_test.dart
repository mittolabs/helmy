import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/project_repository.dart';
import 'package:helmy/data/services/worktrees.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/session.dart';

import '../testing/fake_repositories.dart';

void main() {
  late Directory root;
  late String remote, repo, other;
  late Worktrees git;

  String run(String dir, List<String> args) {
    final r = Process.runSync('git', [
      '-c', 'user.name=Test', '-c', 'user.email=test@helmy.test', //
      '-c', 'init.defaultBranch=main', '-C', dir, ...args,
    ]);
    if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
    return '${r.stdout}'.trim();
  }

  void commit(String dir, String file) {
    File('$dir/$file').writeAsStringSync(file);
    run(dir, ['add', '.']);
    run(dir, ['commit', '-q', '-m', 'add $file']);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('care');
    remote = '${root.path}/remote.git';
    repo = '${root.path}/site';
    other = '${root.path}/other';
    run(root.path, ['init', '-q', '--bare', remote]);
    run(root.path, ['clone', '-q', remote, repo]);
    commit(repo, 'a.txt');
    run(repo, ['push', '-q', '-u', 'origin', 'main']);
    run(remote, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
    run(repo, ['remote', 'set-head', 'origin', 'main']);
    // Someone else, pushing to the same remote.
    run(root.path, ['clone', '-q', remote, other]);
    git = Worktrees(root: '${root.path}/copies');
  });
  tearDown(() => root.delete(recursive: true));

  group('a new copy starts', () {
    test('from the newest on the remote when the checkout has nothing of its own', () async {
      commit(other, 'b.txt');
      run(other, ['push', '-q']);
      final made = await git.create(repo, 'Add the footer');
      expect(File('${made.path}/b.txt').existsSync(), isTrue, reason: 'pushed by someone else');
    });

    test("from the checkout when it has unpushed work, which the session may need", () async {
      commit(repo, 'mine.txt');
      final made = await git.create(repo, 'Use my work');
      expect(File('${made.path}/mine.txt').existsSync(), isTrue);
    });
  });

  group('the default branch is kept current', () {
    test('when the checkout is on it with nothing of its own', () async {
      commit(other, 'b.txt');
      run(other, ['push', '-q']);
      expect(await git.pullIfClean(repo), isTrue);
      expect(File('$repo/b.txt').existsSync(), isTrue);
      expect(await git.pullIfClean(repo), isFalse, reason: 'already current');
    });

    test('never over changes, commits of its own, or another branch', () async {
      commit(other, 'b.txt');
      run(other, ['push', '-q']);
      File('$repo/a.txt').writeAsStringSync('changed');
      expect(await git.pullIfClean(repo), isFalse);
      run(repo, ['checkout', '-q', '--', 'a.txt']);

      commit(repo, 'mine.txt');
      expect(await git.pullIfClean(repo), isFalse);
      run(repo, ['reset', '-q', '--hard', 'HEAD~1']);

      run(repo, ['checkout', '-q', '-b', 'feature']);
      expect(await git.pullIfClean(repo), isFalse);
      expect(File('$repo/b.txt').existsSync(), isFalse);
    });
  });

  test('a branch is merged only once it had work and that work is on main', () async {
    final made = await git.create(repo, 'Footer');
    final branch = made.branch!;
    expect(await git.merged(repo, branch), isFalse, reason: 'no commits yet: not merged');
    commit(made.path!, 'footer.txt');
    expect(await git.merged(repo, branch), isFalse, reason: 'its work is not on main');
    run(repo, ['merge', '-q', '--ff-only', branch]);
    expect(await git.merged(repo, branch), isTrue);
  });

  test('a copy tidied away comes back on its branch', () async {
    final made = await git.create(repo, 'Footer');
    commit(made.path!, 'footer.txt');
    expect(await git.remove(repo, made.path!), isTrue);
    expect(Directory(made.path!).existsSync(), isFalse);
    expect(await git.restore(repo, made.path!, made.branch!), isTrue);
    expect(File('${made.path}/footer.txt').existsSync(), isTrue);
  });

  test('tidying: archived, merged and ownerless copies go; work and busy ones stay', () async {
    Session s(
      String id,
      ({String? path, String? branch, String? error}) c, {
      bool archived = false,
    }) => Session(
      id: id,
      title: id,
      cwd: c.path!,
      level: PermissionLevel.ask,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      repo: repo,
      branch: c.branch,
      archived: archived,
    );
    final archived = await git.create(repo, 'Archived');
    final merged = await git.create(repo, 'Merged');
    commit(merged.path!, 'm.txt');
    run(repo, ['merge', '-q', '--ff-only', merged.branch!]);
    final dirty = await git.create(repo, 'Dirty');
    File('${dirty.path}/wip.txt').writeAsStringSync('work in progress');
    final busy = await git.create(repo, 'Busy');
    final orphan = await git.create(repo, 'Orphan');
    final working = await git.create(repo, 'Working');

    final projects = ProjectRepositoryGit(FakeSettingsRepository(), worktrees: git);
    final done = await projects.tidy(
      [
        s('archived', archived, archived: true),
        s('merged', merged),
        s('dirty', dirty, archived: true),
        s('busy', busy, archived: true),
        s('working', working),
      ],
      working: {'busy'},
    );
    expect(Directory(archived.path!).existsSync(), isFalse);
    expect(Directory(merged.path!).existsSync(), isFalse);
    expect(Directory(orphan.path!).existsSync(), isFalse);
    expect(Directory(dirty.path!).existsSync(), isTrue, reason: 'uncommitted work is never lost');
    expect(Directory(busy.path!).existsSync(), isTrue, reason: 'at work right now');
    expect(Directory(working.path!).existsSync(), isTrue, reason: 'its session goes on');
    expect(done, hasLength(3));
    // Branches stay: the archived session's work is still there to come back to.
    expect(run(repo, ['branch', '--list', archived.branch!]), isNotEmpty);
  });
}
