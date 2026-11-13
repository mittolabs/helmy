import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/schedule_repository.dart';
import 'package:helmy/domain/models/scheduled_task.dart';
import 'package:helmy/ui/schedule/view_models/schedule_view_model.dart';
import 'package:helmy/ui/schedule/widgets/schedule_screen.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chat_screen.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/window_layout.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/ui/shell/widgets/shell_screen.dart';
import 'package:helmy/utils/result.dart';
import 'package:provider/provider.dart';

import 'support/storage.dart';

/// An engine that is only a name in settings: nothing runs.
class _Named implements AgentEngine {
  @override
  Future<List<ModelChoice>> models() async => const [];

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

/// The smallest window macOS allows Helmy (a phone's width), a narrow one, a
/// small laptop's, and a large one.
const _sizes = [Size(360, 640), Size(560, 640), Size(900, 640), Size(1280, 820)];

void main() {
  testWidgets('no screen overflows, at any window size, sidebar open or closed', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Every error drawing a screen, with the screen and size it happened at.
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final what = details.exceptionAsString().split('\n').first.trim();
      // Overflows name the widget that caused them; other errors, a frame of ours.
      final at =
          RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(details.toString())?.group(0) ??
          (details.stack?.toString() ?? '')
              .split('\n')
              .firstWhere((l) => l.contains('package:helmy/'), orElse: () => '');
      overflows.add('${_now ?? ''}: $what ${at.trim()}');
    };
    // Put back even when the test fails, or the failure is lost and the run hangs.
    addTearDown(() => FlutterError.onError = previous);

    late Directory root;
    late SessionRepositoryLocal sessions;
    late SettingsRepository settings;
    late ConversationRepositoryEngines repo;
    late EngineRegistry engines;
    late UsageMeter meter;
    late Session session;
    late ScheduleRepository schedules;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('responsive');
      final dir = root.path;
      // Where app data lives, asked by the Data section.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => dir,
      );
      final storage = storageAt(root);
      sessions = SessionRepositoryLocal(storage);
      settings = SettingsRepositoryLocal(storage);
      // Usage as a real account reports it: windows with a pace to keep to,
      // which Settings draws as bars (a bar once blanked its whole page).
      final reset = DateTime.now().add(const Duration(hours: 2));
      final usage = Usage.ofWindows([
        UsageWindow(
          name: 'Session (5 hours)',
          used: .4,
          resetsAt: reset,
          length: const Duration(hours: 5),
        ),
        UsageWindow(name: 'Weekly', used: .9, resetsAt: reset, length: const Duration(days: 7)),
      ]);
      meter = UsageMeter()
        ..report('codex', usage)
        ..report('claude-work', usage);
      engines = EngineRegistry([
        _Named(
          const EngineInfo(
            id: 'claude-work',
            name: 'Claude Code (a rather long account name for a work machine)',
            capabilities: {Capability.tools},
          ),
        ),
        _Named(const EngineInfo(id: 'codex', name: 'Codex', capabilities: {Capability.tools})),
      ]);
      repo = ConversationRepositoryEngines(
        engines: engines,
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      session =
          (await sessions.create(
                cwd: '/Users/someone/Projects/a-folder-with-a-long-name',
              ) as Ok).value
              as Session;
      await sessions.save(
        session.copyWith(title: 'A session whose title runs on well past any sidebar width'),
      );
      schedules = ScheduleRepositoryLocal(
        storage: storage,
        sessions: sessions,
        conversations: repo,
      );
      await schedules.add(
        name: 'Every weekday morning, sum up what came in overnight across my accounts',
        prompt: 'Sum up my unread mail and new files since yesterday.',
        cwd: '/Users/someone/Projects/a-folder-with-a-long-name',
        level: PermissionLevel.values.first,
        schedule: Schedule(Repeat.values.last, DateTime(2026, 11, 5, 8)),
      );
      repo.of(session.id)
        ..loaded = true
        ..items.addAll([
          UserMessage('Find the budget spreadsheet and summarize what changed this quarter.'),
          // A step titled by its own long description: ends in an ellipsis, not past the column.
          ToolCall(
            id: 't2',
            name: 'Bash',
            input: {
              'command': 'sed -i "" "s/ui-monospace/JetBrains Mono/" design/*.html',
              'description':
                  'Added JetBrains Mono to the font links and the code snippet font stacks on '
                  'both the Home and the Download pages',
            },
          )..result = '',
          AssistantText(
            'a',
            'Here is what changed.\n\n| Line | Q1 | Q2 | Change |\n|---|---|---|---|\n'
                '| Salaries and contractors | 120,000 | 135,000 | +12.5% |\n\n'
                '```\n${'a_very_long_identifier_' * 8}\n```',
          ),
          ToolCall(
            id: 't1',
            name: 'Bash',
            input: {'command': 'find ~/Documents -name "*budget*" ${'-o -name "*.xlsx" ' * 6}'},
          )..result = 'Documents/Finance/2026/Budget.xlsx',
        ]);
    });
    final sidebar = SidebarViewModel(sessions: sessions, conversations: repo, settings: settings);
    final chat = ChatViewModel(sessionId: session.id, sessions: sessions, conversations: repo);

    Future<void> show(Widget page) async {
      // Fresh each time: an overflow is reported once per widget, so a reused
      // one would go unreported on the next screen.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsRepository>.value(value: settings),
            Provider(create: (_) => DesktopService()),
          ],
          child: AshlarApp(
            theme: appTheme,
            darkTheme: appDarkTheme,
            home: ShellScreen(viewModel: sidebar, selectedId: session.id, child: page),
          ),
        ),
      );
      // A blinking cursor never settles: a few frames of fixed length instead.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (final size in _sizes) {
      tester.view.physicalSize = size;
      for (final open in [true, false]) {
        await tester.runAsync(
          () => settings.save(settings.settings.copyWith(sidebarOpen: open, stepsOpen: true)),
        );
        final where =
            '${size.width.toInt()}x${size.height.toInt()} sidebar ${open ? 'open' : 'closed'}';
        _now = '$where, conversation';
        await show(ChatScreen(viewModel: chat));
        // Narrow: the sidebar's button slides it in over the page.
        if (size.width < narrowWindow) {
          _now = '$where, sidebar slid in';
          await tester.tap(find.bySemanticsLabel('Show sidebar'));
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text('Scheduled'), findsWidgets, reason: _now);
          await tester.tapAt(Offset(size.width - 10, size.height / 2));
          await tester.pump(const Duration(milliseconds: 600));
        }
        _now = '$where, scheduled';
        await show(
          ScheduleScreen(
            viewModel: ScheduleViewModel(schedules: schedules, settings: settings),
          ),
        );
        for (final section in SettingsSection.values) {
          _now = '$where, settings ${section.name}';
          final vm = SettingsViewModel(
            settings: settings,
            engines: engines,
            meter: meter,
            memory: MemoryRepositoryEngines(engines),
          )..section = section;
          await show(SettingsScreen(viewModel: vm));
          // Nothing cut off at the window's right edge (a scrollable hides that
          // from the overflow check): every text ends inside the window.
          for (final e in find.byType(RichText).evaluate()) {
            final box = e.renderObject! as RenderBox;
            if (!box.attached || !box.hasSize) continue;
            // A row that scrolls sideways (the tabs) runs past on purpose.
            final scrolls = e.findAncestorWidgetOfExactType<SingleChildScrollView>();
            if (scrolls?.scrollDirection == Axis.horizontal) continue;
            final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
            if (right > size.width + 0.5) {
              final text = (e.widget as RichText).text.toPlainText();
              overflows.add(
                '$_now: "${text.length > 30 ? text.substring(0, 30) : text}" ends at ${right.round()}',
              );
            }
          }
        }
      }
    }
    _now = null;
    await tester.pumpWidget(const SizedBox());
    // Let what the screens left running (a tooltip's delay, say) run out.
    await tester.pump(const Duration(seconds: 10));
    chat.dispose();
    sidebar.dispose();
    repo.dispose();
    await tester.runAsync(() => deleteFolder(root));
    FlutterError.onError = previous;
    expect(overflows.toSet().toList(), isEmpty);
  });
}

String? _now;
