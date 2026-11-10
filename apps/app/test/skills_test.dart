import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/skill_store.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/domain/models/tool_server.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';

import '../testing/fake_repositories.dart';

/// Skills and tools are Helmy's (decided 2026-11-10): one skills folder given
/// to every connection, accounts listed once by their own names, and tool
/// servers added to Helmy given to every connection.
void main() {
  late Directory root;
  late SkillStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('skills');
    store = SkillStore('${root.path}/support/skills');
    await store.load();
  });
  tearDown(() => root.delete(recursive: true));

  test('a skill written in Helmy is a SKILL.md every connection reads', () async {
    final s = await store.create(
      name: 'Release Notes',
      description: 'When writing "release notes" from merged work',
      instructions: 'List each change.\nSay why it matters.',
    );
    expect(s?.name, 'release-notes');
    final md = File('${store.root}/release-notes/SKILL.md').readAsStringSync();
    expect(md, startsWith('---\nname: release-notes\n'));
    expect(SkillStore.read(md, 'x')?.description, 'When writing "release notes" from merged work');
    expect(store.names, {'release-notes'});
  });

  test('a skill folder is copied in, and one without a SKILL.md is refused', () async {
    final from = Directory('${root.path}/mine/tidy')..createSync(recursive: true);
    File('${from.path}/SKILL.md')
        .writeAsStringSync('---\nname: tidy\ndescription: Tidies.\n---\nGo.\n');
    File('${from.path}/notes.txt').writeAsStringSync('kept too');
    expect((await store.addFolder(from.path))?.name, 'tidy');
    expect(File('${store.root}/tidy/notes.txt').existsSync(), isTrue);
    expect(await store.addFolder(root.path), isNull);
    await store.remove('tidy');
    expect(store.skills, isEmpty);
  });

  test('Claude Code gets them as a plugin, Codex through a link', () async {
    final manifest = File('${store.pluginDir}/.claude-plugin/plugin.json');
    expect(manifest.readAsStringSync(), contains('"name": "helmy"'));
    expect(await Link('${store.pluginDir}/skills').target(), store.root);

    final codex = '${root.path}/codex-home';
    await store.linkInto(codex);
    expect(await Link('$codex/skills/helmy').target(), store.root);
    await store.linkInto(codex);
    expect(await Link('$codex/skills/helmy').target(), store.root, reason: 'again, unchanged');
  });

  test("a folder of the person's own where the link would go is left alone", () async {
    final codex = '${root.path}/codex-home';
    Directory('$codex/skills/helmy').createSync(recursive: true);
    await store.linkInto(codex);
    expect(FileSystemEntity.isLinkSync('$codex/skills/helmy'), isFalse);
  });

  test("a Helmy skill's /command is asked for in words any connection follows", () {
    const names = {'release-notes'};
    expect(
      SkillStore.asked('/release-notes for v0.3', names),
      'Use the "release-notes" skill. for v0.3',
    );
    expect(SkillStore.asked('/release-notes', names), 'Use the "release-notes" skill.');
    expect(SkillStore.asked('/review this', names), '/review this', reason: 'not Helmy\'s');
    expect(SkillStore.asked('fix /release-notes', names), 'fix /release-notes');
  });

  test('a tool server reaches each connection in its own form, and is kept', () {
    const web = ToolServer(name: 'github', url: 'https://mcp.example.com/');
    const local = ToolServer(name: 'files', command: 'npx', args: ['-y', 'server-files']);
    expect(web.forClaude, {'type': 'http', 'url': 'https://mcp.example.com/'});
    expect(local.forCodex, {
      'command': 'npx',
      'args': ['-y', 'server-files'],
    });
    expect(web.forAcp(http: false), isNull, reason: 'that agent cannot reach an address');
    expect(local.forAcp(http: false)?['command'], 'npx');
    final back = AppSettings.fromJson(const AppSettings(toolServers: [web, local]).toJson());
    expect([for (final t in back.toolServers) t.name], ['github', 'files']);
    expect(back.toolServers.last.args, ['-y', 'server-files']);
  });

  test('accounts are listed once, by their own names, at their best', () async {
    final vm = SettingsViewModel(
      settings: FakeSettingsRepository(
        const AppSettings(
          toolServers: [ToolServer(name: 'github', url: 'https://x.example')],
        ),
      ),
      engines: EngineRegistry([]),
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(EngineRegistry([])),
    );
    addTearDown(vm.dispose);
    vm.tools['claude'] = (
      commands: const [
        SlashCommand(name: 'review', description: ''),
        SlashCommand(name: 'helmy:tidy', description: ''),
      ],
      servers: const [
        (name: 'claude.ai Gmail', status: 'needs-auth'),
        (name: 'helmy', status: 'connected'),
        (name: 'github', status: 'connected'),
      ],
    );
    vm.tools['claude-work'] = (
      commands: const [
        SlashCommand(name: 'review', description: ''),
        SlashCommand(name: 'tidy', description: ''),
      ],
      servers: const [(name: 'claude.ai Gmail', status: 'connected')],
    );
    expect(vm.accounts, [(name: 'Gmail', status: 'connected')]);
    expect(
      [
        for (final c in vm.skillsFound({'tidy'})) c.name,
      ],
      ['review'],
    );
  });
}
