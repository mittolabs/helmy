import 'package:flutter/services.dart';
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
import 'package:helmy/ui/settings/view_models/settings_index.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';

/// Searching Settings: the results take the sections' place, the page
/// follows the one picked, and Enter goes to the setting itself.
void main() {
  test('words people use find a setting; a title match comes first', () {
    String name(SettingsSection s) => s.name;
    expect(searchSettings('dark', name).first.title, 'Theme');
    expect(searchSettings('battery', name), isEmpty);
    expect(searchSettings('whitespace', name).single.title, 'Hide changes only in spaces');
    expect(searchSettings('send', name).first.title, 'Send with');
    // Every word must match somewhere.
    expect(searchSettings('theme dark', name).first.title, 'Theme');
    expect(searchSettings('theme battery', name), isEmpty);
  });

  testWidgets('results in place of the sections; ↓ shows the next; Enter goes there', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final settings = FakeSettingsRepository(const AppSettings());
    final engines = EngineRegistry([]);
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    );
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

    await tester.enterText(find.bySemanticsLabel('Search settings'), 'wrap');
    await tester.pump(const Duration(milliseconds: 300));
    // The sections give way to what was found, each with its page.
    expect(find.bySemanticsLabel('Wrap long code blocks, in Appearance'), findsOneWidget);
    expect(find.bySemanticsLabel('Memory'), findsNothing);
    // The page shows the first one already.
    expect(vm.section, SettingsSection.appearance);

    await tester.enterText(find.bySemanticsLabel('Search settings'), 'branch');
    await tester.pump(const Duration(milliseconds: 300));
    final found = vm.results;
    expect(found.length, greaterThan(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 300));
    expect(vm.picked, 1);
    expect(vm.target, found[1].title);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(vm.query, isEmpty, reason: 'the search is done with');
    expect(vm.section, found[1].section);
    expect(vm.focusTarget, isTrue);
    expect(find.text(found[1].title), findsWidgets);
    await tester.pump(const Duration(seconds: 2));

    // From anywhere in Settings, / goes back to the search.
    final field = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field.focusNode.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    expect(field.focusNode.hasFocus, isTrue);
  });
}
