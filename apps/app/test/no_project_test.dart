import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/format.dart';
import 'package:helmy/utils/result.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('noproject');
    scratchRoot = '${root.path}/scratch';
  });
  tearDown(() async {
    scratchRoot = null;
    await root.delete(recursive: true);
  });

  test('names a folder of its own "No project", and others by their name', () {
    expect(projectName('${root.path}/scratch/abc'), 'No project');
    expect(projectName('/Users/me/videos'), 'videos');
    expect(isScratch('${root.path}/scratchy/abc'), isFalse);
  });

  test('a session starts without a project in a folder of its own, gone with it', () async {
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final project = Directory('${root.path}/videos')..createSync();
    final s = (await sessions.create(cwd: project.path) as Ok).value as Session;
    repo.of(s.id).loaded = true;
    final vm = ChatViewModel(sessionId: s.id, sessions: sessions, conversations: repo);
    addTearDown(vm.dispose);

    await vm.startWithoutProject();
    final cwd = vm.session!.cwd;
    expect(cwd, '${root.path}/scratch/${s.id}');
    expect(Directory(cwd).existsSync(), isTrue);
    expect(projectName(cwd), 'No project');

    await vm.delete();
    expect(Directory(cwd).existsSync(), isFalse, reason: "Helmy's own folder goes with it");
    expect(project.existsSync(), isTrue);
  });
}
