// A look at one Settings page, on this Mac:
// fvm flutter test integration_test/settings_look_test.dart -d macos \
//   --dart-define=SHOTS=<dir> --dart-define=SECTION=general --dart-define=AT='<a title to scroll to>'
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
const section = String.fromEnvironment('SECTION', defaultValue: 'general');
const at = String.fromEnvironment('AT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('settings page $section', (tester) async {
    tester.view.physicalSize = const Size(1800, 2400);
    tester.view.devicePixelRatio = 2;
    final settings = FakeSettingsRepository(const AppSettings());
    final engines = EngineRegistry([]);
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..show(SettingsSection.values.byName(section));
    final desktop = DesktopService();
    vm.desktop = desktop;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          Provider.value(value: desktop),
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
    Future<void> settle() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    await settle();
    if (at.isNotEmpty) {
      await tester.ensureVisible(find.text(at).first);
      await settle();
    }
    await shot(tester, '$shots/settings-$section.png');
  });
}
