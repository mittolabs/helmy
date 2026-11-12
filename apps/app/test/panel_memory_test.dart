import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/snapshots.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/result.dart';

void main() {
  test('a chat\'s panel is as it was left on coming back, even after Helmy restarts', () async {
    final root = await Directory.systemTemp.createTemp('panel');
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
    final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
    final other = (await sessions.create(cwd: root.path) as Ok).value as Session;

    final vm = ChatViewModel(sessionId: s.id, sessions: sessions, conversations: repo);
    vm.add(.terminal);
    final file = vm.add(.files, focus: false)..filePath = '${root.path}/notes.md';
    vm.focus(file);
    vm.add(.files, focus: false).codeDraft = 'a draft, of the moment';
    vm.resize(512);
    vm.setDesignView({'x': -40, 'y': 12, 's': 0.5});
    await vm.panelSaved;
    vm.dispose();

    // Another chat's panel is its own.
    final elsewhere = ChatViewModel(sessionId: other.id, sessions: sessions, conversations: repo);
    expect(elsewhere.tabs, isEmpty);
    elsewhere.dispose();

    // Read back from disk, as after a restart.
    final again = SessionRepositoryLocal(storage);
    await again.load();
    final back = ChatViewModel(sessionId: s.id, sessions: again, conversations: repo);
    expect(back.tabs.map((t) => t.kind), [SidePanel.terminal, SidePanel.files]);
    expect(back.active?.filePath, '${root.path}/notes.md');
    expect(back.panelOpen, isTrue);
    expect(back.panelWidth, 512);
    expect(back.designView, {'x': -40, 'y': 12, 's': 0.5});
    back.dispose();
  });
}
