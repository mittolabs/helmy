import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connections_setup.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/codex/codex_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';

import '../testing/fake_repositories.dart';
import 'support/storage.dart';

/// Sign-in and who is signed in, as asked, without a browser or a real
/// account.
class _Setup extends ConnectionsSetup {
  _Setup(this.ok, {this.who}) : super(CliLocator(), DesktopService());
  bool ok;
  String? who;
  final signedIn = <(String, String?)>[];

  @override
  Future<bool> signIn(String id, {String? configDir}) async {
    signedIn.add((id, configDir));
    return ok;
  }

  @override
  Future<String?> signedInAs(String kind, String? folder) async => who;
}

void main() {
  late Directory home;
  setUp(() async => home = await Directory.systemTemp.createTemp('accounts'));
  tearDown(() => deleteFolder(home));

  test('a browser sign-in gets a folder named after the account, marked as made', () async {
    final setup = _Setup(true);
    Directory('${home.path}/.claude-work').createSync(); // one the user made
    final made = await setup.addAccount('claude', 'Work', home: home.path);
    expect(made?.id, 'claude-work-2', reason: "the user's own folder is not taken over");
    expect(made?.folder, '${home.path}/.claude-work-2');
    expect((made?.name, made?.kind, made?.made), ('Work', 'claude', true));
    expect(setup.signedIn.single, ('claude', '${home.path}/.claude-work-2'));
    expect(ConnectionsSetup.addedByHelmy(made!.folder), isTrue);

    final again = await setup.addAccount(
      'codex',
      'Personal',
      home: home.path,
      taken: {'codex-personal'},
    );
    expect(again?.id, 'codex-personal-2');
  });

  test('a sign-in that does not finish leaves nothing behind', () async {
    final made = await _Setup(false).addAccount('codex', 'Personal', home: home.path);
    expect(made, isNull);
    expect(home.listSync(), isEmpty);
  });

  test('names become folder names', () {
    expect(ConnectionsSetup.slugOf('Work (2026)'), 'work-2026');
    expect(ConnectionsSetup.slugOf('  '), 'account');
  });

  test("only a folder Helmy made is removed; the user's own stay", () async {
    final setup = _Setup(true);
    final made = await setup.addAccount('claude', 'Work', home: home.path);
    final own = Directory('${home.path}/.claude-mine')..createSync();
    expect(await setup.removeAccount(own.path), isFalse);
    expect(own.existsSync(), isTrue);
    expect(await setup.removeAccount(made!.folder), isTrue);
    expect(Directory(made.folder).existsSync(), isFalse);
  });

  test("a Codex account's email is read from its sign-in", () {
    String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final token = '${part({'alg': 'none'})}.${part({'email': 'tito@helmy.test'})}.sig';
    File('${home.path}/auth.json').writeAsStringSync(
      jsonEncode({
        'tokens': {'id_token': token},
      }),
    );
    expect(ConnectionsSetup.codexEmail(home.path), 'tito@helmy.test');
    expect(ConnectionsSetup.codexEmail('${home.path}/none'), isNull);
  });

  test('accounts are kept in settings, never found by looking in folders', () {
    const a = ConnectionAccount(id: 'claude-work', kind: 'claude', name: 'Work', folder: '/f');
    final back = AppSettings.fromJson(
      jsonDecode(jsonEncode(const AppSettings(accounts: [a]).toJson())) as Map<String, Object?>,
    );
    expect(back.accounts.single.toJson(), a.toJson());
    expect(const AppSettings().toJson().containsKey('accounts'), isFalse);
  });

  test('accounts join and leave the running registry, under their names', () {
    final registry = EngineRegistry([
      CodexEngine(CliLocator()),
    ], account: (a) => CodexEngine(CliLocator(), id: a.id, name: a.name, home: a.folder));
    const a = ConnectionAccount(id: 'codex-personal', kind: 'codex', name: 'Personal');
    registry.add(a);
    registry.add(a);
    expect([for (final e in registry.engines) e.info.id], ['codex', 'codex-personal']);
    expect(registry.infoOf('codex-personal')?.name, 'Codex (Personal)');
    registry.remove('codex-personal');
    expect(registry.byId('codex-personal'), isNull);
  });

  test("a folder already signed in is added as it is, and removing it leaves the folder", () async {
    final settings = FakeSettingsRepository(const AppSettings());
    final engines = EngineRegistry([
      CodexEngine(CliLocator()),
    ], account: (a) => CodexEngine(CliLocator(), id: a.id, name: a.name, home: a.folder));
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..setup = _Setup(true, who: 'tito@helmy.test');
    final own = Directory('${home.path}/.codex-mine')..createSync();
    expect(await vm.signedInAs('codex', own.path), 'tito@helmy.test');
    await vm.addFolder('codex', 'Mine', own.path);
    expect(settings.settings.accounts.single.folder, own.path);
    expect(settings.settings.accounts.single.made, isFalse);
    expect(engines.byId('codex-mine'), isNotNull);
    expect(vm.canRemove('codex-mine'), isTrue);
    expect(vm.canRemove('codex'), isFalse);
    await vm.removeAccount('codex-mine');
    expect(settings.settings.accounts, isEmpty);
    expect(engines.byId('codex-mine'), isNull);
    expect(own.existsSync(), isTrue);
  });

  test('which connections can take another account', () {
    expect(SettingsViewModel.kindOf('claude'), 'claude');
    expect(SettingsViewModel.kindOf('claude-2'), 'claude');
    expect(SettingsViewModel.kindOf('codex-work'), 'codex');
    expect(SettingsViewModel.kindOf('ollama'), isNull);
  });

  test(
    "a Codex account sharing history links the usual one's, and removing it leaves them",
    () async {
      final usual = Directory('${home.path}/.codex')..createSync();
      Directory('${usual.path}/sessions/2026').createSync(recursive: true);
      File('${usual.path}/sessions/2026/talk.jsonl').writeAsStringSync('mine');
      File('${usual.path}/config.toml').writeAsStringSync('model = "x"');
      File('${usual.path}/auth.json').writeAsStringSync('{"usual": true}');
      final setup = _Setup(true);
      final made = await setup.addAccount('codex', 'Work', home: home.path, shareHistory: true);
      final folder = made!.folder;
      expect(FileSystemEntity.isLinkSync('$folder/sessions'), isTrue);
      expect(File('$folder/sessions/2026/talk.jsonl').readAsStringSync(), 'mine');
      expect(FileSystemEntity.isLinkSync('$folder/config.toml'), isTrue);
      expect(File('$folder/auth.json').existsSync(), isFalse, reason: 'its sign-in is its own');

      // Removed: its links go, never what they point at.
      expect(await setup.removeAccount(folder), isTrue);
      expect(Directory(folder).existsSync(), isFalse);
      expect(File('${usual.path}/sessions/2026/talk.jsonl').readAsStringSync(), 'mine');
      expect(File('${usual.path}/config.toml').existsSync(), isTrue);
      expect(File('${usual.path}/auth.json').existsSync(), isTrue);
    },
  );
}
