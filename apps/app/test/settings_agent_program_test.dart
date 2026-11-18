import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';

/// Settings > Connections: an agent says which program runs it, and can be
/// pointed at another, as Claude Code, Codex and Ollama can.
/// An engine that is only a name: nothing runs.
class _Named implements AgentEngine {
  _Named(this.info);
  @override
  final EngineInfo info;
  @override
  Future<List<ModelChoice>> models() async => const [];
  @override
  Future<String?> unavailableReason() async => null;
  @override
  Future<List<MemoryFile>> memoryFiles() async => const [];
  @override
  Future<List<SlashCommand>> commands(String cwd) async => const [];
  @override
  Future<Usage?> readUsage() async => null;
  @override
  Future<List<({String name, String status})>> servers() async => const [];
  @override
  Future<Set<Capability>> connected() async => const {};
  @override
  Future<Answer?> ask(String instructions, String question) async => null;
  @override
  Future<List<MemoryNote>> memoryNotes() async => const [];
  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) => throw UnimplementedError();
}

void main() {
  Future<void> show(WidgetTester tester, ConnectionAccount account) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final settings = FakeSettingsRepository(AppSettings(accounts: [account]));
    final engines = EngineRegistry(
      [],
      account: (a) => _Named(EngineInfo(id: a.id, name: a.name, capabilities: const {})),
    )..add(account);
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..show(SettingsSection.agents);
    vm.chosenAgent = account.id;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          Provider(create: (_) => DesktopService()),
        ],
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: SettingsScreen(viewModel: vm),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('an agent found on this computer says where, with Choose', (tester) async {
    late File cli;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('agent-row');
      cli = await File('${dir.path}/opencode').create();
    });
    await show(
      tester,
      ConnectionAccount(
        id: 'acp.opencode',
        kind: 'acp',
        name: 'OpenCode',
        command: cli.path,
        args: const ['acp'],
        agentId: 'opencode',
      ),
    );
    expect(find.textContaining('Found: '), findsOneWidget);
    expect(find.text('Choose...'), findsWidgets);
    expect(find.text('Find it again'), findsNothing, reason: 'nothing chosen to undo');
    await tester.runAsync(() => cli.parent.delete(recursive: true));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('one whose program has gone says so, and can be pointed at another', (tester) async {
    await show(
      tester,
      const ConnectionAccount(
        id: 'acp.opencode',
        kind: 'acp',
        name: 'OpenCode',
        command: r'C:\Users\sam\AppData\Roaming\npm\opencode.cmd',
        args: ['acp'],
        agentId: 'opencode',
        chosen: true,
      ),
    );
    expect(find.textContaining('Its program was not found: '), findsOneWidget);
    expect(find.text('Choose...'), findsWidgets);
    expect(find.text('Find it again'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
