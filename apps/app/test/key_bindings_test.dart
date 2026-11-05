import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/key_bindings.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:helmy/utils/platform.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';

/// Shortcuts the user changes: recorded by pressing them, refused when
/// another command has them, put back with one press, kept as text.
void main() {
  setUp(() => Desktop.current = .mac);

  test("Helmy's own keys, and a saved choice read back", () {
    expect(AppCommand.newChat.standard.label, '⌘N');
    expect(AppCommand.newThread.standard.label, '⇧⌘N');
    expect(AppCommand.settings.standard.label, '⌘,');
    const mine = KeyBinding(key: LogicalKeyboardKey.keyJ, command: true, alt: true);
    expect(KeyBinding.parse(mine.saved), mine);
    expect(bindingOf(.search, {'search': mine.saved}), mine);
    expect(bindingOf(.search, const {}), AppCommand.search.standard);
  });

  testWidgets('recorded by pressing, refused when taken, reset by its arrow', (tester) async {
    tester.view.physicalSize = const Size(2400, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final settings = FakeSettingsRepository(const AppSettings());
    final engines = EngineRegistry([]);
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..show(.keyboard);
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

    Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }

    await tester.tap(find.bySemanticsLabel('Change keys for Search chats and run actions'));
    await tester.pump();
    expect(find.text('Recording'), findsOneWidget);
    // ⌘N is New chat's: refused, and said so.
    await press(LogicalKeyboardKey.keyN);
    expect(find.text("⌘N is New chat's."), findsOneWidget);
    expect(settings.settings.keys, isEmpty);
    await press(LogicalKeyboardKey.keyJ);
    expect(bindingOf(.search, settings.settings.keys).label, '⌘J');
    expect(find.text('⌘J'), findsOneWidget);
    expect(changedSettings(settings.settings), contains('Shortcuts'));

    await tester.tap(find.bySemanticsLabel('Reset Search chats and run actions'));
    await tester.pump();
    expect(settings.settings.keys, isEmpty);
    expect(find.text('⌘K'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
