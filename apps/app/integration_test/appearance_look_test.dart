// A look at Appearance's fonts, contrast and clock, on this Mac:
// fvm flutter test integration_test/appearance_look_test.dart -d macos --dart-define=SHOTS=<dir>
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
import 'package:helmy/utils/platform.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';
import 'support/shot.dart';

const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('fonts chosen, firmer, 24 hours', (tester) async {
    tester.view.physicalSize = const Size(1800, 2600);
    tester.view.devicePixelRatio = 2;
    final desktop = DesktopService();
    final fonts = await tester.runAsync(desktop.fontFamilies);
    expect(fonts!.all, contains('Avenir'));
    expect(fonts.fixed, contains('Menlo'));
    final settings = FakeSettingsRepository(
      const AppSettings(
        interfaceFont: 'Avenir',
        codeFont: 'Courier New',
        promptFont: 'Georgia',
        contrast: 1,
        clock: .twentyFour,
      ),
    );
    chosenCodeFont = 'Courier New';
    final engines = EngineRegistry([]);
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..show(.appearance);
    vm.desktop = desktop;
    final s = settings.settings;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          Provider.value(value: desktop),
        ],
        child: shootable(
          AshlarApp(
            theme: themeFor(Brightness.dark, font: s.interfaceFont, contrast: s.contrast),
            darkTheme: themeFor(Brightness.dark, font: s.interfaceFont, contrast: s.contrast),
            home: SettingsScreen(viewModel: vm),
          ),
        ),
      ),
    );
    for (var i = 0; i < 40 && vm.fonts == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Sample'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await shot(tester, '$shots/appearance.png');
    expect(find.text('Avenir'), findsOneWidget);
  });
}
