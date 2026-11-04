import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helmy/data/repositories/attention_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/notify_service.dart';
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
      final settings = SettingsRepositoryLocal(storage);
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

  testWidgets('a snoozed session leaves the list, and comes back needing you', (tester) async {
    late Directory root;
    late StorageService storage;
    late SessionRepositoryLocal sessions;
    late ConversationRepositoryEngines repo;
    late Session a, b;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('snooze');
      storage = StorageService(root: () async => root);
      sessions = SessionRepositoryLocal(storage);
      final meter = UsageMeter();
      repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      a = (await sessions.create(cwd: root.path) as Ok).value as Session;
      b = (await sessions.create(cwd: root.path) as Ok).value as Session;
    });
    final settings = SettingsRepositoryLocal(storage);
    final attention = AttentionRepositoryLocal(
      conversations: repo,
      sessions: sessions,
      settings: settings,
      notify: _Quiet(),
    );
    final vm = SidebarViewModel(
      sessions: sessions,
      conversations: repo,
      settings: settings,
      attention: attention,
    );
    bool listed(Session s) => vm.shown.any((x) => x.id == s.id);

    await tester.runAsync(() => vm.snooze(a, DateTime.now().add(const Duration(hours: 1))));
    expect(listed(a), isFalse);
    expect(listed(b), isTrue);

    // Working while snoozed: back in the list for as long as it works.
    repo.of(a.id).busy = true;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    repo.notifyListeners();
    expect(listed(a), isTrue);
    repo.of(a.id).busy = false;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    repo.notifyListeners();

    // Undone.
    await tester.runAsync(vm.undoSnooze);
    expect(listed(a), isTrue);

    // Due a moment from now: it wakes on time, unread, under "Needs you".
    await tester.runAsync(() async {
      await vm.snooze(sessions.byId(a.id)!, DateTime.now().add(const Duration(milliseconds: 300)));
    });
    expect(listed(a), isFalse);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    expect(listed(a), isTrue);
    expect(sessions.byId(a.id)!.snoozedUntil, isNull);
    expect(attention.isUnread(a.id), isTrue);
    expect(vm.groups.first.label, 'Needs you');
    expect(vm.groups.first.sessions.map((s) => s.id), [a.id]);

    expect(
      SidebarViewModel.tomorrowMorning(DateTime(2026, 11, 4, 22, 15)),
      DateTime(2026, 11, 5, 9),
    );
    vm.dispose();
    attention.dispose();
    repo.dispose();
    await tester.runAsync(() async {
      await storage.flush();
      await root.delete(recursive: true);
    });
  });

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

class _Quiet extends NotifyService {
  @override
  Future<bool?> isActive() async => null;
  @override
  Future<void> notify({
    required String sessionId,
    required String title,
    required String body,
    bool thumbsUp = false,
  }) async {}
  @override
  Future<void> badge(int count) async {}
  @override
  Future<void> face(String? face) async {}
}
