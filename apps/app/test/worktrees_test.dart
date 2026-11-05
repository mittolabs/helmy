import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/data/services/worktrees.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/utils/result.dart';

/// A repository with one commit, in a temporary folder.
Future<String> _repo(Directory root) async {
  final repo = await Directory('${root.path}/app').create();
  Future<void> git(List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: repo.path);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  await git(['init', '-q', '-b', 'main']);
  await File('${repo.path}/README.md').writeAsString('hello\n');
  await git(['add', '.']);
  await git(['-c', 'user.name=Test', '-c', 'user.email=test@helmy.test', 'commit', '-qm', 'first']);
  return repo.resolveSymbolicLinksSync();
}

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('worktrees'));
  tearDown(() => root.delete(recursive: true));

  test('a copy gets its own branch and folder, and is kept while it holds work', () async {
    final repo = await _repo(root);
    final copies = Worktrees(root: '${root.path}/copies');
    expect(await copies.repoOf(repo), repo);
    expect(await copies.repoOf(root.path), isNull, reason: 'not a repository');

    final made = await copies.create(repo, 'Fix the login page!');
    expect(made.error, isNull);
    expect(made.branch, matches(RegExp(r'^helmy/fix-the-login-page-[0-9a-f]{4}$')));
    expect(File('${made.path}/README.md').existsSync(), isTrue);
    expect(await copies.uncommitted(made.path!), 0);

    // Uncommitted work in it: it stays.
    await File('${made.path}/notes.txt').writeAsString('mine');
    expect(await copies.remove(repo, made.path!), isFalse);
    expect(Directory(made.path!).existsSync(), isTrue);

    // Clean: it goes, and its branch stays.
    await File('${made.path}/notes.txt').delete();
    expect(await copies.remove(repo, made.path!), isTrue);
    expect(Directory(made.path!).existsSync(), isFalse);
    final branches = await Process.run('git', ['branch'], workingDirectory: repo);
    expect('${branches.stdout}', contains(made.branch!));
  });

  test("a session's first message makes its copy, where the project asks for one", () async {
    final repo = await _repo(root);
    final storage = StorageService(root: () async => Directory('${root.path}/data')..createSync());
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    var own = true;
    final conversations = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
      worktrees: Worktrees(root: '${root.path}/copies'),
      ownCopies: (r) => r == repo && own,
    );
    final s = (await sessions.create(cwd: repo) as Ok).value as Session;
    conversations.of(s.id).loaded = true;
    await conversations.send(sessions.byId(s.id)!, 'Add a dark mode');
    final moved = sessions.byId(s.id)!;
    expect(moved.ownCopy, isTrue);
    expect(moved.repo, repo);
    expect(moved.branch, startsWith('helmy/add-a-dark-mode-'));
    expect(moved.cwd, startsWith('${root.path}/copies/app/'));
    expect(conversations.of(s.id).items.whereType<Notice>().first.text, contains('own branch'));

    // Off for the project: the session works in the folder itself.
    own = false;
    final t = (await sessions.create(cwd: repo) as Ok).value as Session;
    conversations.of(t.id).loaded = true;
    await conversations.send(sessions.byId(t.id)!, 'Something else');
    expect(sessions.byId(t.id)!.ownCopy, isFalse);
    expect(sessions.byId(t.id)!.cwd, repo);
    conversations.dispose();
    await storage.flush();
  });

  test('a project says otherwise than everywhere', () {
    const s = AppSettings(
      ownCopies: false,
      projects: {'/code/app': ProjectSettings(ownCopies: true, level: PermissionLevel.edit)},
    );
    expect(s.ownCopiesIn('/code/app'), isTrue);
    expect(s.ownCopiesIn('/code/other'), isFalse);
    final back = AppSettings.fromJson(s.toJson());
    expect(back.project('/code/app').level, PermissionLevel.edit);
    expect(back.project('/code/other').ownCopies, isNull);
  });

  test('branches named by kind of change, or after a prefix; copies from the remote', () async {
    expect(Worktrees.kindOf('Fix the login page'), 'fix');
    expect(Worktrees.kindOf('Add a dark mode'), 'feat');
    expect(Worktrees.kindOf('Update the README'), 'docs');
    expect(
      Worktrees.branchFor('Fix the login page', semantic: true),
      matches(RegExp(r'^fix/fix-the-login-page-[0-9a-f]{4}$')),
    );
    expect(Worktrees.branchFor('Dark mode', prefix: 'tito/'), startsWith('tito/dark-mode-'));

    // A remote one commit ahead of the checkout: a copy from the remote has it.
    final upstream = await _repo(root);
    final clone = '${root.path}/clone';
    await Process.run('git', ['clone', '-q', upstream, clone]);
    await File('$upstream/NEW.md').writeAsString('newer\n');
    await Process.run('git', ['add', '.'], workingDirectory: upstream);
    await Process.run('git', [
      '-c', 'user.name=Test', '-c', 'user.email=test@helmy.test', 'commit', '-qm', 'second', //
    ], workingDirectory: upstream);
    await Process.run('git', ['checkout', '-q', '-b', 'mine'], workingDirectory: clone);
    final copies = Worktrees(
      root: '${root.path}/copies',
      rules: () => const CopyRules(semantic: true, fromRemote: true),
    );
    final made = await copies.create(clone, 'Add a dark mode');
    expect(made.error, isNull);
    expect(made.branch, startsWith('feat/'));
    expect(File('${made.path}/NEW.md').existsSync(), isTrue, reason: "from the remote's newest");
  });
}
