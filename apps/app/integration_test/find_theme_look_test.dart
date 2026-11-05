// Finding a theme on Open VSX from Appearance, for real, on this Mac:
// fvm flutter test integration_test/find_theme_look_test.dart -d macos --dart-define=SHOTS=<dir>
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Nord found, opened and used', (tester) async {
    tester.view.physicalSize = const Size(1800, 2000);
    tester.view.devicePixelRatio = 2;
    final settings = FakeSettingsRepository(const AppSettings());
    final engines = EngineRegistry([]);
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..show(.appearance);
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
            home: SettingsScreen(viewModel: vm),
          ),
        ),
      ),
    );
    Future<void> wait(bool Function() done, {int seconds = 30}) async {
      for (var i = 0; i < seconds * 5 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
    }

    await wait(() => find.text('Find one...').evaluate().isNotEmpty, seconds: 3);
    await tester.ensureVisible(find.text('Find one...'));
    await tester.pump();
    await tester.tap(find.text('Find one...'));
    await wait(() => find.bySemanticsLabel('Search themes').evaluate().isNotEmpty, seconds: 5);
    await tester.enterText(find.bySemanticsLabel('Search themes'), 'nord');
    await wait(() => find.text('Nord').evaluate().isNotEmpty);
    await shot(tester, '$shots/find-theme.png');
    await tester.tap(find.text('Open').first);
    await wait(
      () => settings.settings.themeImport != null || find.text('Use').evaluate().isNotEmpty,
    );
    if (settings.settings.themeImport == null) await tester.tap(find.text('Use').first);
    await wait(() => settings.settings.themeImport != null);
    expect(settings.settings.palette, Palette.imported);
    // ignore: avoid_print
    print('used: ${settings.settings.themeImport?['name']}');
  });
}
