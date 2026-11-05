// Adding OpenCode from the real ACP registry, installed and checked, on
// this Mac: fvm flutter test integration_test/add_agent_look_test.dart -d macos \
//   --dart-define=SHOTS=<dir> --dart-define=AGENTS=<a folder to install into>
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/acp/acp_engine.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';
import 'support/shot.dart';

const shots = String.fromEnvironment('SHOTS');
const agents = String.fromEnvironment('AGENTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('OpenCode from the registry', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 2;
    final settings = FakeSettingsRepository(const AppSettings());
    final locator = CliLocator();
    final engines = EngineRegistry(
      [ClaudeEngine(locator)],
      account: (a) => AcpEngine(
        locator,
        id: a.id,
        name: a.name,
        command: a.command ?? '',
        args: a.args,
        profile: profileFor(a.agentId ?? ''),
      ),
    );
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..agentsRoot = (() async => agents);

    Future<void> wait(bool Function() done, {int seconds = 30}) async {
      for (var i = 0; i < seconds * 5 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          Provider(create: (_) => DesktopService()),
        ],
        child: shootable(
          AshlarApp(
            theme: themeFor(Brightness.dark),
            darkTheme: themeFor(Brightness.dark),
            home: Builder(
              builder: (context) => GestureDetector(
                onTap: () => addAgent(context, vm),
                child: const SizedBox.expand(child: Text('open')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await wait(() => find.text('OpenCode').evaluate().isNotEmpty);
    await shot(tester, '$shots/agent-1-registry.png');

    await tester.enterText(find.bySemanticsLabel('Search agents'), 'opencode');
    await tester.pump();
    await shot(tester, '$shots/agent-2-search.png');
    await tester.tap(find.bySemanticsLabel('Add OpenCode').first);
    await wait(() => settings.settings.accounts.isNotEmpty, seconds: 300);
    await wait(() => find.text('Add an agent').evaluate().isEmpty, seconds: 120);
    await shot(tester, '$shots/agent-3-done.png');

    final a = settings.settings.accounts.single;
    expect((a.kind, a.agentId, a.made), ('acp', 'opencode', true));
    expect(a.command, startsWith(agents));
    expect(find.text('Add an agent'), findsNothing, reason: 'closed: it checked out ready');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
