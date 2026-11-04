import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/ui/shell/widgets/shell_screen.dart';

void main() {
  testWidgets('the list menu shows each setting with its value, and changes it', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late SidebarViewModel vm;
    late SettingsRepository settings;
    late Directory root;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('menu');
      final storage = StorageService(root: () async => root);
      final sessions = SessionRepositoryLocal(storage);
      settings = SettingsRepositoryLocal(storage);
      final meter = UsageMeter();
      final repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      vm = SidebarViewModel(sessions: sessions, conversations: repo, settings: settings);
    });
    await tester.pumpWidget(
      AshlarApp(
        theme: appTheme,
        darkTheme: appDarkTheme,
        home: ShellScreen(viewModel: vm, selectedId: null, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Show, group and sort sessions'));
    await tester.pumpAndSettle();
    for (final name in ['Show', 'Group by', 'Sort by']) {
      expect(find.text(name), findsOneWidget);
    }
    for (final value in ['Active', 'All', 'None']) {
      expect(find.text(value), findsOneWidget);
    }
    // "Last activity" is both a filter's name and the sort's value.
    expect(find.text('Last activity'), findsNWidgets(2));
    // Into "Show", and pick Archived.
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(settings.settings.show, ShowSessions.archived);
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
