import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/devices.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

void main() {
  test('the device floats out of the panel, and back into it', () async {
    final root = await Directory.systemTemp.createTemp('float');
    addTearDown(() => root.delete(recursive: true));
    final storage = storageAt(root);
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
    final vm = ChatViewModel(
      sessionId: created.id,
      sessions: sessions,
      conversations: repo,
      devices: DeviceService(CliLocator()),
    );

    vm.show(.files);
    vm.show(.device);
    expect(vm.tabs.map((t) => t.kind), [SidePanel.files, SidePanel.device]);

    vm.floatDevice();
    expect(vm.deviceFloating, isTrue);
    expect(vm.tabs.map((t) => t.kind), [SidePanel.files], reason: 'in one place at a time');
    expect(vm.addable, isNot(contains(SidePanel.device)));

    // The agent showing the device leaves it floating, with no second one.
    vm.showDevice();
    expect(vm.tabs.map((t) => t.kind), [SidePanel.files]);

    vm.dockDevice();
    expect(vm.deviceFloating, isFalse);
    expect(vm.panel, SidePanel.device);

    // Floated with nothing else in the panel: the panel hides.
    vm.floatDevice();
    vm.closeTab(vm.tabs.single);
    expect(vm.panelOpen, isFalse);
    vm.closeFloatingDevice();
    expect(vm.deviceFloating, isFalse);
    expect(vm.addable, contains(SidePanel.device));
  });
}
