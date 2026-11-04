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
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';

void main() {
  testWidgets('a changed setting goes back by its row or with all the rest', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final settings = FakeSettingsRepository(
      const AppSettings(theme: .dark, wrapCode: true, sidebarWidth: 400),
    );
    final engines = EngineRegistry([]);
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..section = .appearance;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          Provider(create: (_) => DesktopService()),
        ],
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: SettingsScreen(viewModel: vm),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Two rows changed, each with its way back; the others without.
    expect(find.bySemanticsLabel('Put Theme back to how Helmy has it'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Put Wrap long code blocks back to how Helmy has it'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Put Text size back to how Helmy has it'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Put Theme back to how Helmy has it'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(settings.settings.theme, ThemeChoice.system);
    expect(settings.settings.wrapCode, isTrue, reason: 'only that one');

    // The rest at once, after saying which.
    await tester.tap(find.text('Restore defaults'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('This puts back: Wrap long code blocks.'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(changedSettings(settings.settings), isEmpty);
    expect(settings.settings.sidebarWidth, 400, reason: 'layout is kept');
  });
}
