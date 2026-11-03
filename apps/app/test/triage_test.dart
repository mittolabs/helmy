import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/routing/nav_history.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';
import 'package:flutter/widgets.dart';

void main() {
  test(
    'working sessions come first in a section of their own, and an archive can be undone',
    () async {
      final root = await Directory.systemTemp.createTemp('triage');
      final storage = StorageService(root: () async => root);
      final sessions = SessionRepositoryLocal(storage);
      final meter = UsageMeter();
      final repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      final settings = SettingsRepository(storage);
      final vm = SidebarViewModel(sessions: sessions, conversations: repo, settings: settings);
      Future<Session> make() async =>
          (await sessions.create(cwd: root.path) as Ok).value as Session;
      final a = await make(), b = await make(), c = await make();

      expect(vm.groups.map((g) => g.label), [
        null,
      ], reason: 'nothing needs sorting: one plain list');

      repo.of(b.id).busy = true;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      repo.notifyListeners();
      expect(vm.groups.map((g) => '${g.label}: ${g.sessions.map((s) => s.id).join(",")}'), [
        'Working: ${b.id}',
        'Everything else: ${c.id},${a.id}',
      ]);
      expect(vm.inOrder.first.id, b.id, reason: '⌘1 opens the first one shown');

      await vm.setArchived(c, true);
      expect(vm.shown.any((s) => s.id == c.id), isFalse);
      await vm.undoArchive();
      expect(vm.shown.any((s) => s.id == c.id), isTrue);

      vm.dispose();
      repo.dispose();
      await storage.flush();
      await root.delete(recursive: true);
    },
  );

  testWidgets('back and forward walk where you have been', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        for (final p in ['/', '/a', '/b']) GoRoute(path: p, builder: (_, _) => Text(p)),
      ],
    );
    await tester.pumpWidget(
      WidgetsApp.router(routerConfig: router, color: const Color(0xFF000000)),
    );
    final history = NavHistory(router);
    router.go('/a');
    await tester.pumpAndSettle();
    router.go('/b');
    await tester.pumpAndSettle();

    history.back();
    await tester.pumpAndSettle();
    expect(find.text('/a'), findsOneWidget);
    history.back();
    await tester.pumpAndSettle();
    expect(find.text('/'), findsOneWidget);
    expect(history.canBack, isFalse);
    history.forward();
    await tester.pumpAndSettle();
    expect(find.text('/a'), findsOneWidget);

    // Going somewhere new from the middle drops the old way forward.
    router.go('/b');
    await tester.pumpAndSettle();
    expect(history.canForward, isFalse);
    history.dispose();
  });
}
