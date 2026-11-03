import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/snapshots.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/result.dart';

Future<void> git(String cwd, List<String> args) async {
  final r = await Process.run('git', [
    '-c',
    'user.email=t@helmy.test',
    '-c',
    'user.name=t',
    ...args,
  ], workingDirectory: cwd);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
}

void main() {
  test('a session records the folder before each message, and can put files back', () async {
    final root = await Directory.systemTemp.createTemp('changes');
    final work = await Directory('${root.path}/work').create();
    final cwd = work.path;
    await git(cwd, ['init', '-q']);
    File('$cwd/app.txt').writeAsStringSync('v1\n');
    await git(cwd, ['add', '.']);
    await git(cwd, ['commit', '-q', '-m', 'start']);
    File('$cwd/app.txt').writeAsStringSync('v1\nmine, uncommitted\n');

    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
      snapshots: Snapshots(),
    );
    final s = (await sessions.create(cwd: cwd) as Ok).value as Session;
    await repo.send(s, 'change things');
    expect(sessions.byId(s.id)!.baseline, isNotNull);
    expect(repo.of(s.id).items.whereType<UserMessage>().single.checkpoint, isNotNull);

    // What an agent's edit and a command would leave behind.
    File('$cwd/app.txt').writeAsStringSync('v2\nmine, uncommitted\n');
    File('$cwd/generated.txt').writeAsStringSync('made by a command\n');

    final vm = ChatViewModel(sessionId: s.id, sessions: sessions, conversations: repo);
    final changes = (await vm.changes())!;
    expect(changes.map((c) => c.path), ['app.txt', 'generated.txt']);
    expect(await vm.diffOf('app.txt'), allOf(contains('-v1'), contains('+v2')));

    final ask = repo.of(s.id).items.indexWhere((i) => i is UserMessage);
    expect(vm.canUndoFrom(ask), isTrue);
    expect(await vm.undoFrom(ask), 2);
    expect(File('$cwd/app.txt').readAsStringSync(), 'v1\nmine, uncommitted\n');
    expect(File('$cwd/generated.txt').existsSync(), isFalse);
    expect(await vm.changes(), isEmpty);

    vm.dispose();
    repo.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });
}
