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
  test('the panel holds tabs, and the header says what wants you while it is hidden', () async {
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
    expect(vm.notices, isEmpty, reason: 'nothing changed, nothing running');

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
    expect(vm.changedLines, (added: 1, removed: 1));
    // Said under the message box, not as a notice.
    expect(vm.notices, isEmpty);

    // Work goes to the background: offered while it runs.
    final bg = ToolCall(id: 'b', name: 'Bash', input: {'command': 'sleep 60'})
      ..result = 'running'
      ..background = BackgroundTask('t1');
    repo.of(created.id).items.add(bg);
    expect(vm.notices, [SidePanel.background]);
    bg.background!.status = .completed;
    expect(vm.notices, isEmpty);

    // A notice opens its tab; tabs gather, one showing at a time.
    vm.show(.changes);
    expect((vm.panel, vm.tabs.length), (SidePanel.changes, 1));
    expect(vm.notices, isEmpty, reason: 'the panel is open');
    vm.show(.background);
    expect((vm.panel, vm.tabs.length), (SidePanel.background, 2));
    vm.show(.changes);
    expect((vm.panel, vm.tabs.length), (SidePanel.changes, 2), reason: 'the open tab, not another');

    // Hidden, the tabs stay; shown again, as they were.
    vm.togglePanel();
    expect((vm.panel, vm.tabs.length), (null, 2));
    vm.togglePanel();
    expect(vm.panel, SidePanel.changes);

    // A page goes to the browser tab showing; + adds another beside it.
    vm.preview('https://example.com/a');
    vm.preview('https://example.com/b');
    expect(vm.tabs.where((t) => t.kind == SidePanel.preview), hasLength(1));
    expect(vm.previewUrl, 'https://example.com/b');
    final second = vm.add(SidePanel.preview);
    expect(vm.tabs.where((t) => t.kind == SidePanel.preview), hasLength(2));
    expect(vm.active, second);

    // Closing the one showing shows the one to its right, as browsers do;
    // closing all hides the panel.
    expect(vm.tabs.map((t) => t.kind), [
      SidePanel.changes,
      SidePanel.preview,
      SidePanel.preview,
      SidePanel.background,
    ]);
    vm.closeTab(second);
    expect(vm.active?.kind, SidePanel.background);
    for (final tab in [...vm.tabs]) {
      vm.closeTab(tab);
    }
    expect(vm.tabs, isEmpty);
    expect(vm.panelOpen, isFalse);

    // Code opens in a reusable tab; unsaved work must be saved or discarded.
    await vm.editFile('source.dart');
    final code = vm.active!;
    expect(code.filePath, '${root.path}/source.dart');
    await vm.editFile('source.dart');
    expect(vm.active, same(code));
    expect(vm.tabs, hasLength(1));
    code.hasUnsavedEdits = true;
    vm.closeTab(code);
    expect(vm.tabs, contains(code));
    code.hasUnsavedEdits = false;
    vm.closeTab(code);
    expect(vm.tabs, isEmpty);

    // Local code links, including line anchors, stay inside the app.
    await vm.open('file://${root.path}/linked.dart#L12');
    expect(vm.active!.filePath, '${root.path}/linked.dart');
    vm.closeTab(vm.active!);
    await vm.open('linked.dart:12');
    expect(vm.active!.filePath, '${root.path}/linked.dart');
    vm.closeTab(vm.active!);
    vm.editCode('print("draft");', 'dart');
    final draft = vm.active!;
    expect(draft.codeDraft, 'print("draft");');
    expect(draft.filePath, isNull);
    vm.closeTab(draft);
    expect(vm.tabs, contains(draft));
    vm.show(SidePanel.files);
    expect(vm.active!.codeDraft, isNull, reason: 'Files still opens its browser');
    for (final tab in [...vm.tabs]) {
      tab.hasUnsavedEdits = false;
      vm.closeTab(tab);
    }

    // Dragged widths are kept within reason.
    vm.resize(2000);
    expect(vm.panelWidth, 900);

    // Expanded, the panel has the page; closing it ends that too.
    vm.show(.changes);
    expect(vm.panel, SidePanel.changes);
    vm.toggleExpanded();
    expect(vm.panelExpanded, isTrue);
    vm.closePanel();
    expect((vm.panel, vm.panelExpanded), (null, false));
    vm.toggleExpanded();
    expect(vm.panelExpanded, isFalse, reason: 'nothing open to expand');

    // The panel is saved in turn, after the change that asked for it: wait
    // for the last of those, then for the files they write.
    await vm.panelSaved;
    vm.dispose();
    repo.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });

  test('enough changed, the Changes panel opens by itself, until closed there', () async {
    final root = await Directory.systemTemp.createTemp('panels-open');
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
    void edit(String name) => repo
        .of(created.id)
        .items
        .add(
          ToolCall(
            id: name,
            name: 'Edit',
            input: {'file_path': '${root.path}/$name', 'old_string': 'a', 'new_string': 'b'},
          )..result = 'ok',
        );
    edit('a.txt');
    edit('b.txt');
    await vm.countChanges(turnEnded: true);
    expect(vm.panelOpen, isFalse, reason: 'two files: not yet');
    edit('c.txt');
    await vm.countChanges(turnEnded: true);
    expect(vm.panel, SidePanel.changes, reason: 'three files: worth seeing');
    vm.closePanel();
    edit('d.txt');
    await vm.countChanges(turnEnded: true);
    expect(vm.panelOpen, isFalse, reason: 'closed here: it stays closed');
    await vm.panelSaved;
    vm.dispose();
    repo.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });
}
