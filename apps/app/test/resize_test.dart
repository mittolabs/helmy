import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chat_screen.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/ui/shell/widgets/shell_screen.dart';
import 'package:helmy/utils/result.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('the panel and the sidebar widen by their edges, and the panel expands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late ChatViewModel vm;
    late SettingsRepository settings;
    late SidebarViewModel sidebar;
    late Session session;
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('expand');
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
      final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
      repo.of(s.id)
        ..loaded = true
        ..items.add(UserMessage('hi'));
      session = s;
      sidebar = SidebarViewModel(sessions: sessions, conversations: repo, settings: settings);
      vm = ChatViewModel(
        sessionId: s.id,
        sessions: sessions,
        conversations: repo,
        settings: settings,
      );
    });
    vm.toggle(SidePanel.background);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          Provider(create: (_) => DesktopService()),
        ],
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: ShellScreen(
            viewModel: sidebar,
            selectedId: session.id,
            child: ChatScreen(viewModel: vm),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // The panel's edge: dragged left, the panel widens by as much.
    final before = vm.panelWidth;
    final edge = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Divider');
    expect(edge, findsOneWidget);
    await tester.drag(edge, const Offset(-80, 0), kind: PointerDeviceKind.mouse, touchSlopX: 0);
    await tester.pump();
    expect(vm.panelWidth, closeTo(before + 80, 1), reason: 'the panel edge dragged');

    // The sidebar's edge: dragged right, it widens and the width is kept.
    final sidebarEdge = find.bySemanticsLabel('Sidebar width');
    expect(sidebarEdge, findsOneWidget);
    await tester.drag(
      sidebarEdge,
      const Offset(60, 0),
      kind: PointerDeviceKind.mouse,
      touchSlopX: 0,
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(
      settings.settings.sidebarWidth,
      closeTo(272 + 60, 1),
      reason: 'the sidebar edge dragged',
    );

    final button = find.bySemanticsLabel('Expand');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 300));
    expect(vm.panelExpanded, isTrue, reason: 'the press reached the view model');
    expect(
      find.bySemanticsLabel('Back beside the chat'),
      findsOneWidget,
      reason: 'and the panel shows expanded',
    );
  });
}
