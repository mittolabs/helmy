import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connections_setup.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/codex/codex_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';

/// Sign-in as asked, without a browser or a real account.
class _Setup extends ConnectionsSetup {
  _Setup(this.ok) : super(CliLocator(), DesktopService());
  bool ok;
  final signedIn = <(String, String?)>[];

  @override
  Future<bool> signIn(String id, {String? configDir}) async {
    signedIn.add((id, configDir));
    return ok;
  }
}

void main() {
  late Directory home;
  setUp(() async => home = await Directory.systemTemp.createTemp('accounts'));
  tearDown(() => home.delete(recursive: true));

  test('another account gets the next folder beside the usual one, marked as added', () async {
    final setup = _Setup(true);
    Directory('${home.path}/.claude-2').createSync(); // one the user made
    final made = await setup.addAccount('claude', home: home.path);
    expect(made?.id, 'claude-3');
    expect(made?.folder, '${home.path}/.claude-3');
    expect(setup.signedIn.single, ('claude', '${home.path}/.claude-3'));
    expect(ConnectionsSetup.addedByHelmy(made!.folder), isTrue);
    expect(ConnectionsSetup.addedByHelmy('${home.path}/.claude-2'), isFalse);

    final codex = await setup.addAccount('codex', home: home.path);
    expect(codex?.id, 'codex-2');
  });

  test('a sign-in that does not finish leaves nothing behind to be found', () async {
    final made = await _Setup(false).addAccount('codex', home: home.path);
    expect(made, isNull);
    expect(Directory('${home.path}/.codex-2').existsSync(), isFalse);
  });

  test("only an account Helmy added can be removed; the user's own stay", () async {
    final setup = _Setup(true);
    final made = await setup.addAccount('claude', home: home.path);
    final own = Directory('${home.path}/.claude-work')..createSync();
    expect(await setup.removeAccount(own.path), isFalse);
    expect(own.existsSync(), isTrue);
    expect(await setup.removeAccount(made!.folder), isTrue);
    expect(Directory(made.folder).existsSync(), isFalse);
  });

  test('every Codex account on the Mac is found, each with its own home', () {
    Directory('${home.path}/.codex-work').createSync();
    Directory('${home.path}/.codex-notes.bak').createSync();
    final found = CodexEngine.discover(CliLocator(), home.path);
    expect([for (final e in found) e.info.id], ['codex', 'codex-work']);
    expect(found.last.home, '${home.path}/.codex-work');
    expect(found.first.home, isNull);
  });

  test('accounts join and leave the running registry', () {
    final registry = EngineRegistry([
      ...CodexEngine.discover(CliLocator(), home.path),
    ], account: (id, folder) => CodexEngine(CliLocator(), id: id, home: folder));
    registry.add('codex-2', '${home.path}/.codex-2');
    registry.add('codex-2', '${home.path}/.codex-2');
    expect([for (final e in registry.engines) e.info.id], ['codex', 'codex-2']);
    expect(registry.infoOf('codex-2')?.name, 'Codex (codex-2)');
    registry.remove('codex-2');
    expect(registry.byId('codex-2'), isNull);
  });

  test('which connections can take another account', () {
    expect(SettingsViewModel.kindOf('claude'), 'claude');
    expect(SettingsViewModel.kindOf('claude-2'), 'claude');
    expect(SettingsViewModel.kindOf('codex-work'), 'codex');
    expect(SettingsViewModel.kindOf('ollama'), isNull);
  });
}
