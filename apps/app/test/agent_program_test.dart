import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/acp/acp_registry.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';

import '../testing/fake_repositories.dart';

/// A program at [path] whose help names [mode] (or nothing), as an agent's
/// command-line program does.
File fakeProgram(String path, {String? mode}) {
  final f = File(path)..createSync(recursive: true);
  f.writeAsStringSync(
    '#!/bin/sh\necho "Commands:"\n${mode == null ? '' : 'echo "  $mode   start as an agent"'}\n',
  );
  Process.runSync('chmod', ['+x', f.path]);
  return f;
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('agent-program-'));
  tearDown(() async => dir.delete(recursive: true));

  SettingsViewModel make() {
    const account = ConnectionAccount(
      id: 'acp.opencode',
      kind: 'acp',
      name: 'OpenCode',
      command: 'opencode',
      args: ['acp'],
      agentId: 'opencode',
    );
    // Any engine stands in for the agent: what is checked is which program
    // the account is saved with, and that the engine is made again.
    final engines = EngineRegistry(
      [],
      account: (a) => ClaudeEngine(CliLocator(), id: a.id, name: '${a.name} ${a.command}'),
    );
    final settings = FakeSettingsRepository(const AppSettings(accounts: [account]));
    engines.add(account);
    return SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    );
  }

  test('choosing OpenCode Desktop itself uses the program inside it', () async {
    final app = '${dir.path}/OpenCode.app';
    final cli = fakeProgram('$app/Contents/Resources/opencode-cli', mode: 'acp');
    final vm = make();
    addTearDown(vm.dispose);
    expect(await vm.chooseAgentProgram('acp.opencode', app), isNull);
    final a = vm.settings.accounts.single;
    expect(a.command, cli.path);
    expect(a.chosen, isTrue);
    expect(a.args, ['acp'], reason: 'started the same way');
  }, skip: Platform.isWindows);

  test('a program without the mode Helmy needs is refused, and nothing changes', () async {
    final other = fakeProgram('${dir.path}/OpenCode-old', mode: 'serve');
    final vm = make();
    addTearDown(vm.dispose);
    final why = await vm.chooseAgentProgram('acp.opencode', other.path);
    expect(why, contains("doesn't have the 'acp' mode"));
    expect(why, contains('or the OpenCode app itself'));
    expect(vm.settings.accounts.single.command, 'opencode');
    expect(vm.settings.accounts.single.chosen, isFalse);
  }, skip: Platform.isWindows);

  test("on Windows, the program beside OpenCode's app, in its resources", () {
    final exe = '${dir.path}/ai.opencode.desktop/OpenCode.exe';
    File(exe).createSync(recursive: true);
    final cli = File('${dir.path}/ai.opencode.desktop/resources/opencode-cli.exe')
      ..createSync(recursive: true);
    expect(programIn(exe, 'opencode', os: 'linux'), exe, reason: 'no .exe resources on Linux');
    expect(
      programIn(exe, 'opencode', os: 'windows'),
      cli.path.replaceAll('/', r'\'),
      skip: !Platform.isWindows,
    );
    expect(programIn(cli.path, 'opencode', os: 'windows'), cli.path, reason: 'the program itself');
  });

  test('a saved account remembers that its program was chosen', () {
    const a = ConnectionAccount(id: 'acp.x', kind: 'acp', command: '/x', chosen: true);
    expect(ConnectionAccount.fromJson(a.toJson()).chosen, isTrue);
    expect(ConnectionAccount.fromJson(const ConnectionAccount(id: 'y').toJson()).chosen, isFalse);
  });
}
