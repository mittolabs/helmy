// A look at Settings > Archive and About, on this Mac:
// fvm flutter test integration_test/archive_about_look_test.dart -d macos --dart-define=SHOTS=<dir>
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import '../test/support/storage.dart';
import '../testing/fake_repositories.dart';
import 'support/shot.dart';

const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('archive, then about', (tester) async {
    tester.view.physicalSize = const Size(1240, 1400);
    tester.view.devicePixelRatio = 2;
    final root = Directory.systemTemp.createTempSync('archive-look');
    final storage = storageAt(root);
    final sessions = SessionRepositoryLocal(storage);
    final chats = ChatRepository(storage, sessions);
    final settings = FakeSettingsRepository(const AppSettings());
    final meter = UsageMeter();
    final engines = EngineRegistry([]);
    late SidebarViewModel list;
    await tester.runAsync(() async {
      await chats.load();
      for (final title in ['Budget for the trip', 'Logo ideas']) {
        final s =
            (await sessions.create(cwd: '/Users/sam/work/site', title: title) as Ok).value
                as Session;
        await sessions.save(s.copyWith(archived: true));
      }
    });
    list = SidebarViewModel(
      sessions: sessions,
      conversations: ConversationRepositoryEngines(
        engines: engines,
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      ),
      settings: settings,
      chats: chats,
    );
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: meter,
      memory: MemoryRepositoryEngines(engines),
    )..show(.archive);

    Future<void> settle() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          ChangeNotifierProvider<SidebarViewModel>.value(value: list),
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
    await settle();
    await shot(tester, '$shots/archive.png');
    expect(find.text('Logo ideas'), findsOneWidget);
    await tester.tap(find.text('Unarchive').first);
    await settle();
    expect(sessions.sessions.where((s) => s.archived), hasLength(1));

    vm.show(.about);
    await settle();
    await tester.ensureVisible(find.text('Show licenses'));
    await settle();
    await tester.tap(find.text('Show licenses'));
    // A test build reads no license notices (the test binding skips them);
    // the app reads them from its NOTICES file.
    for (var i = 0; i < 8 && find.textContaining('license notices').evaluate().isEmpty; i++) {
      await settle();
    }
    // ignore: avoid_print
    print(
      'reading: ${find.text('Reading...').evaluate().length}, button: ${find.text('Show licenses').evaluate().length}',
    );
    await shot(tester, '$shots/about.png');
    expect(find.text('Show licenses'), findsNothing);
  });
}
