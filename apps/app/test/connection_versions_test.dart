import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connections_setup.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';
import 'package:helmy/data/services/engines/codex/codex_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';

import '../testing/fake_repositories.dart';

/// Versions as asked, and updates that bring a connection up to date.
class _Setup extends ConnectionsSetup {
  _Setup() : super(CliLocator(), DesktopService());
  final installed = {'claude': '2.1.318', 'codex': '0.162.1'};
  final newest = <String, String?>{'claude': '2.1.318', 'codex': '0.166.0'};
  final updated = <String>[];

  @override
  Future<String?> installedVersion(String kind) async => installed[kind];
  @override
  Future<String?> latestVersion(String kind) async => newest[kind];
  @override
  Future<bool> update(String kind) async {
    updated.add(kind);
    installed[kind] = newest[kind]!;
    return true;
  }
}

void main() {
  test('a version is read out of what a program says', () {
    expect(ConnectionsSetup.versionIn('2.1.318 (Claude Code)'), '2.1.318');
    expect(ConnectionsSetup.versionIn('codex-cli 0.162.1'), '0.162.1');
    expect(ConnectionsSetup.versionIn('ollama version is 0.40.14'), '0.40.14');
    expect(ConnectionsSetup.versionIn('v0.40.14'), '0.40.14');
    expect(ConnectionsSetup.versionIn('no version'), isNull);
  });

  test('newer compares part by part, not as text', () {
    expect(ConnectionsSetup.newer('0.166.0', '0.162.1'), isTrue);
    expect(ConnectionsSetup.newer('2.1.10', '2.1.9'), isTrue);
    expect(ConnectionsSetup.newer('2.1.318', '2.1.318'), isFalse);
    expect(ConnectionsSetup.newer('1.9', '1.10'), isFalse);
  });

  test('every account of a program is one connection to update', () {
    expect(ConnectionsSetup.kindOf('claude-work'), 'claude');
    expect(ConnectionsSetup.kindOf('codex-2'), 'codex');
    expect(ConnectionsSetup.kindOf('ollama'), 'ollama');
  });

  test('what is behind is listed, and Update all brings it up to date', () async {
    final setup = _Setup();
    final engines = EngineRegistry([
      ClaudeEngine(CliLocator()),
      ClaudeEngine(CliLocator(), id: 'claude-2'),
      CodexEngine(CliLocator()),
    ]);
    final vm = SettingsViewModel(
      settings: FakeSettingsRepository(),
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..setup = setup;
    addTearDown(vm.dispose);
    expect(vm.kinds, ['claude', 'codex']);
    await vm.checkVersions();
    expect(vm.outdated, ['codex']);
    expect(await vm.updateAll(), 1);
    expect(setup.updated, ['codex'], reason: 'only what was behind');
    expect(vm.outdated, isEmpty);
    expect(vm.versions['codex']?.installed, '0.166.0');

    // Unknown stays unknown: no newest version, nothing claimed behind.
    setup.newest['claude'] = null;
    await vm.checkVersions();
    expect(vm.versions['claude']?.latest, isNull);
    expect(vm.outdated, isEmpty);
  });
}
