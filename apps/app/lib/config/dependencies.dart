import 'dart:io';

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
  final settings = SettingsRepository(storage);
  final meter = UsageMeter(storage: storage);
  await (sessions.load(), settings.load(), meter.load()).wait;
  return (storage: storage, sessions: sessions, settings: settings, meter: meter);
}

List<SingleChildWidget> providers(Loaded loaded) => [
  Provider.value(value: loaded.storage),
  ChangeNotifierProvider.value(value: loaded.settings),
  ChangeNotifierProvider.value(value: loaded.meter),
  Provider(create: (_) => CliLocator()),
  // Add an engine here and the router starts using it. The order breaks ties
  // before any engine has reported its usage.
  Provider(
    create: (context) => EngineRegistry([
      // Every Claude Code account on the machine, each with its own limits.
      ...ClaudeEngine.discover(context.read(), Platform.environment['HOME'] ?? ''),
      CodexEngine(context.read()),
      // A model on this Mac, for when nothing online can answer: directly for a
      // message that needs no tools, through Codex's agent for one that does.
      OllamaChatEngine(model: () => loaded.settings.settings.ollamaModel),
      CodexEngine.local(context.read(), model: () => loaded.settings.settings.ollamaModel),
    ]),
  ),
  Provider<EngineRouter>(
    create: (context) =>
        HeadroomRouter(context.read(), margin: () => loaded.settings.settings.switching.margin),
  ),
  Provider(create: (context) => MemoryRepository(context.read())),
  ChangeNotifierProvider<SessionRepository>.value(value: loaded.sessions),
  ChangeNotifierProvider<ConversationRepository>(
    create: (context) => ConversationRepositoryEngines(
      engines: context.read(),
      router: context.read(),
      meter: context.read(),
      storage: context.read(),
      sessions: context.read(),
      enabled: (id) => !loaded.settings.settings.disabledEngines.contains(id),
      rules: () => loaded.settings.settings.rules,
      snapshots: Snapshots(),
      decider: Decider(model: () => loaded.settings.settings.ollamaModel),
    ),
  ),
  Provider(create: (_) => NotifyService()),
  Provider(create: (context) => ChatExport(context.read(), context.read())),
  Provider(create: (_) => DesktopService()),
  // Not lazy: tasks run on time whether or not their page was opened.
  ChangeNotifierProvider(
    lazy: false,
    create: (context) => ScheduleRepository(
      storage: context.read(),
      sessions: context.read(),
      conversations: context.read(),
    )..start(),
  ),
  // Not lazy: it has to be listening before anything finishes.
  ChangeNotifierProvider(
    lazy: false,
    create: (context) => AttentionRepository(
      conversations: context.read(),
      sessions: context.read(),
      settings: context.read(),
      notify: context.read(),
    ),
  ),
];
