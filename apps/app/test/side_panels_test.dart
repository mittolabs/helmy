import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/result.dart';

void main() {
  test('the header offers a panel only when the session has something for it', () async {
    final root = await Directory.systemTemp.createTemp('panels');
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
    final created = (await sessions.create(cwd: root.path) as Ok).value as Session;
    repo.of(created.id).loaded = true;
    final vm = ChatViewModel(sessionId: created.id, sessions: sessions, conversations: repo);
    await vm.countChanges();
    expect(vm.panels, isEmpty, reason: 'nothing changed, nothing running');

    // An agent edits a file (no git here: its own report is what is known).
    repo
        .of(created.id)
        .items
        .add(
          ToolCall(
            id: 'e',
            name: 'Edit',
            input: {'file_path': '${root.path}/a.txt', 'old_string': 'a', 'new_string': 'b'},
          )..result = 'ok',
        );
    await vm.countChanges();
    expect(vm.changedFiles, 1);
    expect(vm.panels, [SidePanel.changes]);

    // Work goes to the background: offered while it runs.
    final bg = ToolCall(id: 'b', name: 'Bash', input: {'command': 'sleep 60'})
      ..result = 'running'
      ..background = BackgroundTask('t1');
    repo.of(created.id).items.add(bg);
    expect(vm.panels, [SidePanel.changes, SidePanel.background]);
    bg.background!.status = .completed;
    expect(vm.panels, [SidePanel.changes]);

    // One panel at a time: a button shows its view, replacing the other, and
    // closes it when it is already showing. An open one stays offered.
    vm.toggle(.changes);
    expect(vm.panel, SidePanel.changes);
    vm.toggle(.background);
    expect(vm.panel, SidePanel.background);
    expect(vm.panels, contains(SidePanel.background));
    vm.toggle(.background);
    expect(vm.panel, isNull);

    // Dragged widths are kept within reason.
    vm.resize(2000);
    expect(vm.panelWidth, 900);

    vm.dispose();
    repo.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });
}
