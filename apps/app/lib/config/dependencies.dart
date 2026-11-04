import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../data/repositories/attention_repository.dart';
import '../data/repositories/conversation_repository.dart';
import '../data/repositories/conversation_repository_engines.dart';
import '../data/repositories/memory_repository.dart';
import '../data/repositories/schedule_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/session_repository_local.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/cli_locator.dart';
import '../data/services/browser/browser_host.dart';
import '../data/services/browser/browser_tools.dart';
import '../data/services/chromium/chromium_service.dart';
import '../data/services/devices.dart';
import '../data/services/editors.dart';
import '../data/services/history_import.dart';
import '../data/services/pull_requests.dart';
import '../utils/format.dart';
import '../data/services/sim_input.dart';
import '../data/services/engines/claude/claude_engine.dart';
import '../data/services/engines/codex/codex_engine.dart';
import '../data/services/engines/decider.dart';
import '../data/services/engines/engine_registry.dart';
import '../data/services/engines/ollama/ollama_chat_engine.dart';
import '../data/services/engines/engine_router.dart';
import '../data/services/engines/usage_meter.dart';
import '../data/services/chat_export.dart';
import '../data/services/desktop_service.dart';
import '../data/services/notify_service.dart';
import '../data/services/snapshots.dart';
import '../data/services/storage_service.dart';
import '../utils/platform.dart';
import '../data/services/helmy_tools.dart';
import '../data/services/watch_service.dart';
import '../data/services/worktrees.dart';
import '../data/services/connections_setup.dart';
import '../data/repositories/ship_repository.dart';
import '../data/services/shipping.dart';
import '../data/services/fixes.dart';
import '../ui/chat/widgets/player.dart' show PoppedOut;
import '../data/repositories/project_repository.dart';

/// What is read from disk before the first frame, so the app opens where it was.
typedef Loaded = ({
  StorageService storage,
  SessionRepository sessions,
  SettingsRepository settings,
  UsageMeter meter,
});

Future<Loaded> load() async {
  final storage = StorageService();
  final sessions = SessionRepositoryLocal(storage);
  final settings = SettingsRepositoryLocal(storage);
  final meter = UsageMeter(storage: storage);
  await (sessions.load(), settings.load(), meter.load()).wait;
  // Sessions started without a project each get a folder here.
  scratchRoot = '${(await getApplicationSupportDirectory()).path}/scratch';
  return (storage: storage, sessions: sessions, settings: settings, meter: meter);
}

List<SingleChildWidget> providers(Loaded loaded) => [
  Provider.value(value: loaded.storage),
  ChangeNotifierProvider.value(value: loaded.settings),
  ChangeNotifierProvider.value(value: loaded.meter),
  Provider(create: (_) => CliLocator()),
  Provider(create: (context) => WatchService(context.read())),
  // Taps on iOS simulators through Helmy's resident helper: milliseconds.
  Provider(
    create: (context) {
      final locator = context.read<CliLocator>();
      return SimInput(
        helper: () async =>
            (await rootBundle.load('assets/helmy/bin/sim_input')).buffer.asUint8List(),
        appData: getApplicationSupportDirectory,
        axe: () => locator.find('axe'),
      );
    },
    dispose: (_, input) => input.dispose(),
  ),
  Provider(create: (context) => DeviceService(context.read(), input: context.read())),
  // Open pull requests across every project, through GitHub's command.
  Provider(create: (context) => PullRequests(context.read())),
  // Conversations from Claude Code and Codex on this Mac, to bring in.
  Provider(create: (_) => HistoryImport()),
  // The apps a project opens in, asked of macOS once.
  Provider(create: (_) => EditorService()),
  // A Chromium browser for Preview, once asked for; ended with the app.
  Provider(
    create: (_) => ChromiumService(appData: getApplicationSupportDirectory),
    dispose: (_, c) => unawaited(c.stop()),
  ),
  // The page each session's agent works: its Preview panel's, or one in the
  // background.
  Provider(create: (context) => BrowserHost(chromium: context.read())),
  // Helmy's own tools (watching a video), served to every connection.
  Provider(
    lazy: false,
    create: (context) => HelmyTools(
      context.read(),
      context.read<DeviceService>(),
      BrowserTools(context.read<BrowserHost>()),
      context.read<BrowserHost>().showDevice,
    ),
    dispose: (_, tools) => unawaited(tools.close()),
  ),
  // Add an engine here and the router starts using it. The order breaks ties
  // before any engine has reported its usage.
  Provider(
    create: (context) => EngineRegistry(
      [
        // Every Claude Code and Codex account on the machine, each with its own
        // limits.
        ...ClaudeEngine.discover(context.read(), homeDir, tools: context.read()),
        ...CodexEngine.discover(context.read(), homeDir, tools: context.read()),
        // A model on this Mac, for when nothing online can answer: directly for a
        // message that needs no tools, through Codex's agent for one that does.
        OllamaChatEngine(model: () => loaded.settings.settings.ollamaModel),
        CodexEngine.local(
          context.read(),
          model: () => loaded.settings.settings.ollamaModel,
          tools: context.read(),
        ),
      ],
      // Another account, added in Settings: Claude Code's or Codex's.
      account: (id, folder) => id.startsWith('claude')
          ? ClaudeEngine(context.read(), id: id, configDir: folder, tools: context.read())
          : CodexEngine(context.read(), id: id, home: folder, tools: context.read()),
    ),
  ),
  Provider<EngineRouter>(
    create: (context) =>
        HeadroomRouter(context.read(), margin: () => loaded.settings.settings.switching.margin),
  ),
  Provider<MemoryRepository>(create: (context) => MemoryRepositoryEngines(context.read())),
  ChangeNotifierProvider<SessionRepository>.value(value: loaded.sessions),
  ChangeNotifierProvider<ConversationRepository>(
    create: (context) {
      final repo = ConversationRepositoryEngines(
        engines: context.read(),
        router: context.read(),
        meter: context.read(),
        storage: context.read(),
        sessions: context.read(),
        enabled: (id) => !loaded.settings.settings.disabledEngines.contains(id),
        rules: () => loaded.settings.settings.rules,
        snapshots: Snapshots(),
        worktrees: Worktrees(),
        ownCopies: (repo) => loaded.settings.settings.ownCopiesIn(repo),
        decider: Decider(model: () => loaded.settings.settings.ollamaModel),
      );
      // Known from launch, and again whenever connections are turned on or off.
      unawaited(repo.checkReach());
      loaded.settings.addListener(() => unawaited(repo.checkReach()));
      return repo;
    },
  ),
  Provider(create: (_) => NotifyService()),
  Provider(create: (context) => ChatExport(context.read(), context.read())),
  Provider(create: (_) => DesktopService()),
  // A video popped out to a corner of the window: one for the app.
  ChangeNotifierProvider(create: (_) => PoppedOut()),
  // Getting the connections ready: after what it uses.
  Provider(create: (context) => ConnectionsSetup(context.read(), context.read())),
  Provider(
    create: (context) => Fixes(context.read(), context.read(), context.read<DeviceService>()),
  ),
  Provider<ProjectRepository>(create: (context) => ProjectRepositoryGit(context.read())),
  // Not lazy: tasks run on time whether or not their page was opened.
  ChangeNotifierProvider<ScheduleRepository>(
    lazy: false,
    create: (context) => ScheduleRepositoryLocal(
      storage: context.read(),
      sessions: context.read(),
      conversations: context.read(),
    )..start(),
  ),
  // Not lazy: it has to be listening before anything finishes.
  ChangeNotifierProvider<AttentionRepository>(
    lazy: false,
    create: (context) => AttentionRepositoryLocal(
      conversations: context.read(),
      sessions: context.read(),
      settings: context.read(),
      notify: context.read(),
    ),
  ),
  // Not lazy either: watched checks are followed from launch.
  ChangeNotifierProvider<ShipRepository>(
    lazy: false,
    create: (context) => ShipRepositoryGit(
      shipping: Shipping(context.read()),
      sessions: context.read(),
      conversations: context.read(),
      notify: context.read(),
    ),
  ),
];
