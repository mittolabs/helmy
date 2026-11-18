import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connection_installer.dart';
import 'package:helmy/data/services/connections_setup.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';
import 'package:helmy/data/services/engines/codex/codex_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/ollama/ollama_chat_engine.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';

import '../testing/fake_repositories.dart';

/// Setup with Codex not installed and nothing real run.
class _Setup extends ConnectionsSetup {
  _Setup() : super(CliLocator(), DesktopService());
  final states = {
    'claude': SetupState.ready,
    'codex': SetupState.missing,
    'ollama': SetupState.ready,
  };
  final asked = <String>[];
  bool installs = true;

  @override
  Future<List<ConnectionCheck>> check() async => [
    for (final e in states.entries) (id: e.key, name: e.key, does: '', state: e.value),
  ];

  @override
  Future<String?> install(String id, {void Function(InstallStep step)? step}) async {
    asked.add('install $id');
    step?.call((doing: 'Downloading, 40 of 120 MB…', done: 1 / 3));
    if (seen != null) seen!();
    if (installs) states[id] = SetupState.signedOut;
    return installs ? null : "It didn't install: the download at github.com didn't answer.";
  }

  /// Called mid-install, to see what is shown meanwhile.
  void Function()? seen;

  @override
  Future<bool> signIn(String id, {String? configDir}) async {
    asked.add('sign in $id');
    states[id] = SetupState.ready;
    return true;
  }

  @override
  Future<String?> installedVersion(String kind) async => null;
  @override
  Future<String?> latestVersion(String kind) async => null;
}

void main() {
  SettingsViewModel make(_Setup setup) {
    final engines = EngineRegistry([
      ClaudeEngine(CliLocator()),
      CodexEngine(CliLocator()),
      OllamaChatEngine(model: () => null),
      CodexEngine.local(CliLocator(), model: () => null),
    ]);
    return SettingsViewModel(
      settings: FakeSettingsRepository(),
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..setup = setup;
  }

  test('removing takes a connection out of Helmy only, and it can be added back', () async {
    final setup = _Setup();
    final vm = make(setup);
    addTearDown(vm.dispose);
    expect(vm.used.map((a) => a.info.id), ['claude', 'codex', 'ollama-chat', 'ollama']);
    expect(vm.addable, isEmpty);

    await vm.removeConnection('claude');
    expect(vm.used.map((a) => a.info.id), isNot(contains('claude')));
    expect(vm.addable.map((a) => a.name), ['Claude Code']);
    expect(setup.asked, isEmpty, reason: 'nothing signed out or uninstalled');

    expect(await vm.addConnection('claude'), isNull);
    expect(vm.used.map((a) => a.info.id), contains('claude'));
    expect(vm.addable, isEmpty);
  });

  test("Ollama's two connections come and go as one", () async {
    final vm = make(_Setup());
    addTearDown(vm.dispose);
    await vm.removeConnection('ollama-chat');
    expect(vm.used.map((a) => a.info.id), ['claude', 'codex']);
    expect(vm.addable.map((a) => a.name), ['Ollama']);
    await vm.addConnection(vm.addable.single.id);
    expect(vm.used.length, 4);
  });

  test('adding one that is not installed installs it and signs it in first', () async {
    final setup = _Setup();
    final vm = make(setup);
    addTearDown(vm.dispose);
    await vm.removeConnection('codex');
    InstallStep? shown;
    setup.seen = () => shown = vm.installing;
    expect(await vm.addConnection('codex'), isNull);
    expect(setup.asked, ['install codex', 'sign in codex']);
    // How far along, while it installs; nothing once it has.
    expect(shown?.doing, 'Downloading, 40 of 120 MB…');
    expect(shown?.done, closeTo(1 / 3, 0.001));
    expect(vm.installing, isNull);
    expect(vm.used.map((a) => a.info.id), contains('codex'));
  });

  test('when it cannot be made ready, it stays out and says why', () async {
    final setup = _Setup()..installs = false;
    final vm = make(setup);
    addTearDown(vm.dispose);
    await vm.removeConnection('codex');
    final why = await vm.addConnection('codex');
    // The reason it gives, not a page to go and read.
    expect(why, "It didn't install: the download at github.com didn't answer.");
    expect(vm.used.map((a) => a.info.id), isNot(contains('codex')));
  });

  test('a problem is fixed where it shows, with the press its state needs', () async {
    final setup = _Setup();
    final vm = make(setup);
    addTearDown(vm.dispose);
    await vm.checkSetup();
    expect(vm.fixFor('codex'), 'Install');
    expect(vm.fixFor('claude'), isNull, reason: 'ready: nothing for setup to fix');
    expect(await vm.fixConnection('codex'), isNull);
    expect(vm.fixFor('codex'), isNull);
  });
}
