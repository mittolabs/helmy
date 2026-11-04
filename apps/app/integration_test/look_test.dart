// Pictures of Helmy's main screens, with real fonts, for judging its look:
// fvm flutter test integration_test/look_test.dart -d macos --dart-define=SHOTS=<folder>
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/chromium/chromium_service.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/devices.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chat_screen.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/ui/shell/widgets/empty_screen.dart';
import 'package:helmy/ui/shell/widgets/command_palette.dart';
import 'package:helmy/ui/shell/widgets/shell_screen.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';
import 'package:helmy/utils/result.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

/// An engine that is only a name in settings: nothing runs.
class _Named implements AgentEngine {
  _Named(this.info);
  @override
  final EngineInfo info;
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
  Future<String?> ask(String instructions, String question) async => null;
  @override
  Future<List<MemoryNote>> memoryNotes() async => const [];
  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) => throw UnimplementedError();
}

const shots = String.fromEnvironment('SHOTS');
const window = Size(1200, 850);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the main screens, in dark', (tester) async {
    late SessionRepositoryLocal sessions;
    late SettingsRepository settings;
    late ConversationRepositoryEngines repo;
    late EngineRegistry engines;
    late UsageMeter meter;
    late Session session;
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('look');
      final storage = StorageService(root: () async => root);
      sessions = SessionRepositoryLocal(storage);
      settings = SettingsRepositoryLocal(storage);
      meter = UsageMeter();
      engines = EngineRegistry([
        _Named(
          const EngineInfo(id: 'claude', name: 'Claude Code', capabilities: {Capability.tools}),
        ),
        _Named(
          const EngineInfo(
            id: 'codex',
            name: 'Codex',
            capabilities: {Capability.tools, Capability.imageGeneration},
          ),
        ),
      ]);
      repo = ConversationRepositoryEngines(
        engines: engines,
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      for (final (title, cwd) in const [
        ('Plan the launch email', '/Users/someone/Projects/site'),
        ('Fix the flaky upload test', '/Users/someone/Projects/app'),
        ('Sum up the budget changes', '/Users/someone/Documents'),
      ]) {
        final s = (await sessions.create(cwd: cwd) as Ok).value as Session;
        await sessions.save(s.copyWith(title: title));
        session = s;
      }
      await settings.save(settings.settings.copyWith(sidebarOpen: true, stepsOpen: true));
      repo.of(session.id)
        ..loaded = true
        ..items.addAll([
          UserMessage('Find the budget spreadsheet and summarize what changed this quarter.'),
          ToolCall(
            id: 't1',
            name: 'Bash',
            input: {'command': 'find ~/Documents -name "*budget*.xlsx"'},
          )..result = 'Documents/Finance/2026/Budget.xlsx',
          AssistantText(
            'a',
            'Spending rose **8%** this quarter, mostly salaries.\n\n'
                '| Line | Q1 | Q2 | Change |\n|---|---|---|---|\n'
                '| Salaries | 120,000 | 135,000 | +12.5% |\n'
                '| Software | 18,000 | 17,200 | -4.4% |\n\n'
                'Travel was flat. Want me to draft a note for the team?',
          ),
        ]);
    });
    final sidebar = SidebarViewModel(sessions: sessions, conversations: repo, settings: settings);
    final chat = ChatViewModel(
      sessionId: session.id,
      sessions: sessions,
      conversations: repo,
      devices: DeviceService(CliLocator()),
    );
    final key = GlobalKey();

    Future<void> shoot(String name, Widget page, {String? selected, Widget? over}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsRepository>.value(value: settings),
            ChangeNotifierProvider.value(value: sidebar),
            Provider(create: (_) => DesktopService()),
          ],
          child: AshlarApp(
            theme: appTheme,
            darkTheme: appDarkTheme,
            themeMode: .dark,
            home: OverflowBox(
              alignment: .topLeft,
              minWidth: window.width,
              maxWidth: window.width,
              minHeight: window.height,
              maxHeight: window.height,
              child: RepaintBoundary(
                key: key,
                child: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: window),
                    child: Stack(
                      children: [
                        ShellScreen(viewModel: sidebar, selectedId: selected, child: page),
                        if (over != null) ...[
                          const Positioned.fill(child: ColoredBox(color: Color(0x99000000))),
                          Positioned.fill(child: over),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      if (shots.isEmpty) return;
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await shoot('home', const EmptyScreen());
    await shoot('chat', ChatScreen(viewModel: chat), selected: session.id);
    // A panel beside the conversation, then over the page.
    chat.toggle(.device);
    await shoot('panel', ChatScreen(viewModel: chat), selected: session.id);
    chat.toggleExpanded();
    await shoot('panel-expanded', ChatScreen(viewModel: chat), selected: session.id);
    chat.closePanel();
    // Settings, a sheet over the conversation: each section, and a search.
    for (final section in [...SettingsSection.values, null]) {
      final vm =
          SettingsViewModel(
              settings: settings,
              engines: engines,
              meter: meter,
              memory: MemoryRepositoryEngines(engines),
            )
            ..chromium = ChromiumService(appData: () async => Directory.systemTemp)
            ..section = section ?? .general;
      if (section == null) vm.search('notif');
      await shoot(
        'settings-${section?.name ?? 'search'}',
        ChatScreen(viewModel: chat),
        selected: session.id,
        over: SettingsScreen(viewModel: vm),
      );
    }
    // The ⌘K palette over a session, with a router as the app has.
    final router = GoRouter(
      initialLocation: '/s/${session.id}',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        GoRoute(
          path: '/s/:id',
          builder: (_, _) => ShellScreen(
            viewModel: sidebar,
            selectedId: session.id,
            child: ChatScreen(viewModel: chat),
          ),
        ),
      ],
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          ChangeNotifierProvider.value(value: sidebar),
          Provider(create: (_) => DesktopService()),
        ],
        child: AshlarApp.router(
          routerConfig: router,
          theme: appTheme,
          darkTheme: appDarkTheme,
          themeMode: .dark,
          builder: (context, child) => OverflowBox(
            alignment: .topLeft,
            minWidth: window.width,
            maxWidth: window.width,
            minHeight: window.height,
            maxHeight: window.height,
            child: RepaintBoundary(
              key: key,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: window),
                child: child!,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    unawaited(showPalette(tester.element(find.byType(ChatScreen)), sidebar));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    if (shots.isNotEmpty) {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shots/palette.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
