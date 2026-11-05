// A look at adding an account, with a real sign-in check, on this Mac:
// fvm flutter test integration_test/add_account_look_test.dart -d macos \
//   --dart-define=FOLDER=<a signed-in Claude Code folder> --dart-define=SHOTS=<dir>
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connections_setup.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:integration_test/integration_test.dart';

import '../testing/fake_repositories.dart';

const folder = String.fromEnvironment('FOLDER');
const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('adding a folder already signed in', (tester) async {
    final settings = FakeSettingsRepository(const AppSettings());
    final engines = EngineRegistry([
      ClaudeEngine(CliLocator()),
    ], account: (a) => ClaudeEngine(CliLocator(), id: a.id, name: a.name, configDir: a.folder));
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..setup = ConnectionsSetup(CliLocator(), DesktopService());

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    Future<void> shot(String name) => tester
        .runAsync(() async {
          final id = (await Process.run('swift', [
            '$shots/../winpid.swift',
            '$pid',
          ])).stdout.toString().trim();
          await Process.run('screencapture', ['-x', '-o', '-l', id, '$shots/$name.png']);
        })
        .then((_) {});

    await tester.pumpWidget(
      AshlarApp(
        theme: appTheme.copyWith(density: -1),
        darkTheme: appDarkTheme.copyWith(density: -1),
        home: Builder(
          builder: (context) => GestureDetector(
            onTap: () => addAccount(context, vm, 'claude'),
            child: const SizedBox.expand(child: Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle();
    await shot('1-open');

    await tester.enterText(find.bySemanticsLabel('Account name'), 'Second');
    await tester.tap(find.bySemanticsLabel('A signed-in folder'));
    await settle();
    await tester.enterText(find.bySemanticsLabel('Folder'), folder);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 60 && vm.settings.accounts.isEmpty; i++) {
      await settle();
      if (find.textContaining('Signed in').evaluate().isNotEmpty) break;
    }
    await shot('2-checked');
    expect(find.textContaining('Signed in as'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Add'));
    await settle();
    await shot('3-added');
    expect(settings.settings.accounts.single.folder, folder);
    expect(settings.settings.accounts.single.made, isFalse);
    expect(engines.byId('claude-second')?.info.name, 'Claude Code (Second)');
  });
}
