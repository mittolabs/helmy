import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/domain/vscode_theme.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/ashlar/input.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';

/// A theme of one's own: made from Helmy's colors, one changed by hex.
void main() {
  testWidgets('made from Helmy\'s own, with the page color changed', (tester) async {
    tester.view.physicalSize = const Size(2400, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
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
        child: AshlarApp(
          theme: appDarkTheme,
          darkTheme: appDarkTheme,
          home: SettingsScreen(viewModel: vm),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // Below the palettes and accents: scrolled to first.
    await tester.ensureVisible(find.text('Make one...'));
    await tester.pump();
    await tester.tap(find.text('Make one...'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Theme colors'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate((w) => w is Input && w.semanticLabel == 'Page color'),
      '#112233',
    );
    await tester.enterText(
      find.byWidgetPredicate((w) => w is Input && w.semanticLabel == 'Theme name'),
      'Harbor',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));
    final t = importedThemeFromJson(settings.settings.themeImport)!;
    expect((t.name, t.dark), ('Harbor', true));
    expect(t.colors['background'], 0xFF112233);
    expect(t.colors['foreground'], appDarkTheme.colors.foreground.toARGB32());
    expect(settings.settings.palette, Palette.imported);
    await tester.pump(const Duration(seconds: 2));
  });
}
