import '../domain/models/settings.dart';
import '../data/services/engines/agent_engine.dart';

import 'package:flutter/widgets.dart';

import '../data/services/engines/acp/acp_engine.dart';

import 'dart:async';
import 'dart:io';

import '../data/services/mac/mac_actions.dart';
import '../data/services/mac/mac_tools.dart';

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
import '../data/repositories/chat_repository.dart';
import '../data/repositories/chat_keeper.dart';
import '../data/services/cloud_writer.dart';
import '../data/services/remote/remote_host.dart';
import '../data/services/remote/remote_server.dart';
import '../data/services/local_writer.dart';
import '../data/services/chat_tools.dart';
import '../data/services/history_import.dart';
import '../data/services/turn_log.dart';
import '../data/services/pull_requests.dart';
import '../data/services/window_snapshots.dart';
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
import '../data/services/helmy_tools.dart';
import '../data/services/watch_service.dart';
import '../data/services/worktrees.dart';
import '../data/services/storage_cleanup.dart';
import '../data/repositories/restart_keeper.dart';
import '../data/services/connections_setup.dart';
import '../data/repositories/ship_repository.dart';
import '../data/services/shipping.dart';
import '../data/services/fixes.dart';
import '../ui/chat/widgets/player.dart' show PoppedOut;
import '../data/repositories/project_repository.dart';
import '../data/services/webhooks.dart';
import '../data/repositories/stash_repository.dart';

/// What is read from disk before the first frame, so the app opens where it was.
typedef Loaded = ({
  StorageService storage,
  SessionRepository sessions,
  SettingsRepository settings,
  UsageMeter meter,
  ChatRepository chats,
});

Future<Loaded> load() async {
  final storage = StorageService();
  final sessions = SessionRepositoryLocal(storage);
  final settings = SettingsRepositoryLocal(storage);
  final meter = UsageMeter(storage: storage);
  await (sessions.load(), settings.load(), meter.load()).wait;
  // Every thread in a chat (decision 0014): those from before chats get one.
  final chats = ChatRepository(storage, sessions);
  await chats.load();
  // Sessions started without a project each get a folder here.
  scratchRoot = '${(await getApplicationSupportDirectory()).path}/scratch';
  return (storage: storage, sessions: sessions, settings: settings, meter: meter, chats: chats);
}

List<SingleChildWidget> providers(Loaded loaded) => [
  Provider.value(value: loaded.storage),
  ChangeNotifierProvider.value(value: loaded.settings),
  ChangeNotifierProvider.value(value: loaded.meter),
  ChangeNotifierProvider.value(value: loaded.chats),
  // Drafts put aside with ⌘S, to go on with in any chat.
  ChangeNotifierProvider(create: (context) => StashRepository(loaded.storage)..load()),
  Provider(create: (_) => CliLocator(chosen: () => loaded.settings.settings.programs)),
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
  // What each turn cost, measured (decision 0014), on this Mac only.
  Provider(create: (_) => TurnLog(appData: getApplicationSupportDirectory)),
  // Conversations from Claude Code and Codex on this Mac, to bring in.
  Provider(create: (_) => HistoryImport()),
  // Any app's window, snapshotted into the message being written.
  Provider(create: (_) => WindowSnapshots(appData: getApplicationSupportDirectory)),
  // Helmy's own leftovers, old and referred to by nothing: once a day.
  Provider(
    lazy: false,
    create: (context) {
      final cleanup = StorageCleanup(context.read(), appData: getApplicationSupportDirectory);
      unawaited(cleanup.runIfDue());
      return cleanup;
    },
  ),
  // The apps a project opens in, asked of macOS once.
  Provider(create: (_) => EditorService()),
  // A Chromium browser for Preview, once asked for; ended with the app.
  Provider(
    // Any left running by a Helmy that was ended without stopping it goes now.
    create: (_) => ChromiumService(
      appData: getApplicationSupportDirectory,
      profile: () => loaded.settings.settings.browserProfile,
    )..cleanUpSoon(),
    dispose: (_, c) => unawaited(c.stop()),
    // Made at launch, so the cleaning happens then.
    lazy: false,
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
  // Threads' own copies, made as Settings says.
  Provider(
    create: (_) => Worktrees(
      rules: () {
        final s = loaded.settings.settings;
        return CopyRules(
          prefix: s.copyPrefix,
          semantic: s.copySemantic,
          fromRemote: s.copyFromRemote,
          folder: s.copyFolder,
        );
      },
    ),
  ),
  // Add an engine here and the router starts using it. The order breaks ties
  // before any engine has reported its usage.
  Provider(
    create: (context) => EngineRegistry(
      [
        // The usual Claude Code and Codex accounts, and those added in
        // Settings, each with its own limits. Folders are never gone looking
        // for: an account is used only once the user adds it.
        ClaudeEngine(context.read(), tools: context.read()),
        CodexEngine(context.read(), tools: context.read()),
        for (final a in loaded.settings.settings.accounts) _account(context, a),
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
      account: (a) => _account(context, a),
    ),
  ),
  Provider<EngineRouter>(
    create: (context) => HeadroomRouter(
      context.read(),
      margin: () => loaded.settings.settings.switching.margin,
      bestAt: (kind) => loaded.settings.settings.bestFor(kind),
    ),
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
        worktrees: context.read<Worktrees>(),
        log: context.read(),
        ownCopies: (repo) => loaded.settings.settings.ownCopiesIn(repo),
        decider: Decider(model: () => loaded.settings.settings.ollamaModel),
      );
      // Known from launch, and again whenever connections are turned on or off.
      unawaited(repo.checkReach());
      loaded.settings.addListener(() => unawaited(repo.checkReach()));
      return repo;
    },
  ),
  // The rest of a session's chat, for its agent (decision 0014).
  Provider(
    lazy: false,
    create: (context) {
      final tools = context.read<HelmyTools>();
      final sessions = context.read<SessionRepository>();
      tools.devicesAllowed = () => loaded.settings.settings.agentDevices;
      if (Platform.isMacOS) tools.mac = MacTools(MacActions());
      tools.browserAllowed = (id) {
        final s = id == null ? null : sessions.byId(id);
        return s == null || loaded.settings.settings.browserIn(s.repo ?? s.cwd);
      };
      return tools.chats = ChatTools(
        sessions: context.read(),
        chats: context.read(),
        conversations: context.read(),
        log: context.read(),
      );
    },
  ),
  // Events from outside, into the threads given an address.
  Provider(
    lazy: false,
    create: (context) => Webhooks(
      sessions: context.read(),
      conversations: context.read(),
      signing: (id) => loaded.settings.settings.hookSigning[id],
    )..start(),
    dispose: (_, w) => unawaited(w.stop()),
  ),
  // Chats kept current as threads go quiet, on the model on this Mac.
  Provider(create: (_) => LocalWriter(model: () => loaded.settings.settings.ollamaModel)),
  Provider(
    lazy: false,
    create: (context) => ChatKeeper(
      sessions: context.read(),
      conversations: context.read(),
      chats: context.read(),
      writer: context.read(),
      log: context.read(),
      // Where this Mac has no model: the cheapest in the cloud.
      cloud: CloudWriter(
        context.read(),
        context.read(),
        (id) => !loaded.settings.settings.disabledEngines.contains(id),
      ),
      naming: () => loaded.settings.settings.namingNote,
    ),
    dispose: (_, k) => k.dispose(),
  ),
  Provider(create: (_) => NotifyService()),
  Provider(create: (context) => ChatExport(context.read(), context.read())),
  // Chats at work when Helmy closed, carried on now; then kept track of.
  Provider(
    lazy: false,
    create: (context) {
      final keeper = RestartKeeper(
        context.read(),
        context.read(),
        context.read(),
        enabled: () => loaded.settings.settings.carryOnAfterRestart,
      );
      unawaited(keeper.start());
      return keeper;
    },
    dispose: (_, k) => k.dispose(),
  ),
  Provider(create: (_) => DesktopService()),
  // A video popped out to a corner of the window: one for the app.
  ChangeNotifierProvider(create: (_) => PoppedOut()),
  // Getting the connections ready: after what it uses.
  Provider(create: (context) => ConnectionsSetup(context.read(), context.read())),
  Provider(
    create: (context) => Fixes(context.read(), context.read(), context.read<DeviceService>()),
  ),
  Provider<ProjectRepository>(
    create: (context) => ProjectRepositoryGit(context.read(), worktrees: context.read<Worktrees>()),
  ),
  // Not lazy: tasks run on time whether or not their page was opened.
  ChangeNotifierProvider<ScheduleRepository>(
    lazy: false,
    create: (context) => ScheduleRepositoryLocal(
      storage: context.read(),
      sessions: context.read(),
      conversations: context.read(),
      worktrees: context.read<Worktrees>(),
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
  // A paired phone reaching Helmy here, while settings let it.
  ChangeNotifierProvider<RemoteHost>(
    lazy: false,
    create: (context) => RemoteHost(
      RemoteServer(sessions: context.read(), conversations: context.read(), chats: context.read()),
      context.read<SettingsRepository>(),
    ),
  ),
];

/// The engine for an account added in Settings.
AgentEngine _account(BuildContext context, ConnectionAccount a) => a.kind == 'acp'
    ? AcpEngine(
        context.read(),
        id: a.id,
        name: a.name,
        command: a.command ?? '',
        args: a.args,
        profile: profileFor(a.agentId ?? ''),
        tools: context.read(),
      )
    : a.kind == 'claude'
    ? ClaudeEngine(
        context.read(),
        id: a.id,
        name: a.name,
        configDir: a.folder,
        tools: context.read(),
      )
    : CodexEngine(context.read(), id: a.id, name: a.name, home: a.folder, tools: context.read());
