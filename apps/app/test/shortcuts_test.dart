import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:helmy/ui/core/window_layout.dart';
import 'package:helmy/utils/result.dart';
import 'package:provider/provider.dart';

typedef _World = ({
  Directory root,
  StorageService storage,
  SessionRepositoryLocal sessions,
  SettingsRepository settings,
  ConversationRepositoryEngines repo,
});

Future<_World> _world(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late _World w;
  await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('keys');
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    w = (
      root: root,
      storage: storage,
      sessions: sessions,
      settings: SettingsRepositoryLocal(storage),
      repo: ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      ),
    );
  });
  return w;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('⌘1 to ⌘9 open the sessions in the order the list shows them', (tester) async {
    final w = await _world(tester);
    late Session a, b;
    await tester.runAsync(() async {
      a = (await w.sessions.create(cwd: w.root.path) as Ok).value as Session;
      b = (await w.sessions.create(cwd: w.root.path) as Ok).value as Session;
    });
    final vm = SidebarViewModel(sessions: w.sessions, conversations: w.repo, settings: w.settings);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ShellScreen(
            viewModel: vm,
            selectedId: null,
            child: const Focus(autofocus: true, child: Text('home')),
          ),
        ),
        GoRoute(
          path: '/s/:id',
          builder: (_, state) => ShellScreen(
            viewModel: vm,
            selectedId: state.pathParameters['id'],
            // Focus inside the page, as the composer has it in the app.
            child: Focus(autofocus: true, child: Text('session ${state.pathParameters['id']}')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      AshlarApp.router(routerConfig: router, theme: appTheme, darkTheme: appDarkTheme),
    );
    await tester.pumpAndSettle();
    // Newest first: b, then a.
    expect(vm.inOrder.map((s) => s.id), [b.id, a.id]);
    await _press(tester, LogicalKeyboardKey.digit2);
    expect(find.text('session ${a.id}'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.digit1);
    expect(find.text('session ${b.id}'), findsOneWidget);
    // Past the end of the list: nothing happens.
    await _press(tester, LogicalKeyboardKey.digit9);
    expect(find.text('session ${b.id}'), findsOneWidget);
    vm.dispose();
    w.repo.dispose();
    await tester.runAsync(() => w.root.delete(recursive: true));
  });

  testWidgets('⌘F finds in the conversation, and Enter walks the matches', (tester) async {
    final w = await _world(tester);
    late ChatViewModel vm;
    await tester.runAsync(() async {
      final s = (await w.sessions.create(cwd: w.root.path) as Ok).value as Session;
      w.repo.of(s.id)
        ..loaded = true
        ..items.addAll([
          UserMessage('where is the budget spreadsheet?'),
          AssistantText('a', 'The budget is in Finance/2026.xlsx.'),
          UserMessage('thanks'),
          AssistantText('b', 'Anything else on the budget?'),
        ]);
      vm = ChatViewModel(sessionId: s.id, sessions: w.sessions, conversations: w.repo);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: w.settings),
          Provider(create: (_) => DesktopService()),
        ],
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: ChatScreen(viewModel: vm),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.keyF);
    await tester.enterText(find.byType(EditableText).first, 'budget');
    await tester.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, 'pineapple');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    // Escape closes it.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsNothing);
    vm.dispose();
    w.repo.dispose();
    await tester.runAsync(() => w.root.delete(recursive: true));
  });

  testWidgets('a double-click on the title bar\'s empty space goes to macOS, not one on a button', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('helmy/notify'),
      (call) async => calls.add(call.method),
    );
    var pressed = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            height: 50,
            child: TitleBar(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => pressed++,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: ColoredBox(color: Color(0xFF000000)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // On the button: two presses, both at once, and no zoom.
    await tester.tapAt(const Offset(20, 20));
    expect(pressed, 1, reason: 'not held up waiting for a second click');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(20, 20));
    expect(pressed, 2);
    expect(calls, isEmpty);
    // Clicks at given moments, as a real mouse stamps them.
    var pointer = 10;
    Future<void> clickAt(Offset at, int ms) async {
      final stamp = Duration(milliseconds: ms);
      tester.binding.handlePointerEvent(
        PointerDownEvent(pointer: ++pointer, position: at, timeStamp: stamp),
      );
      tester.binding.handlePointerEvent(
        PointerUpEvent(pointer: pointer, position: at, timeStamp: stamp),
      );
      await tester.pump();
    }

    // On empty space: one click does nothing, two close together do.
    await clickAt(const Offset(300, 20), 10000);
    expect(calls, isEmpty);
    await clickAt(const Offset(300, 20), 10200);
    expect(calls, ['titleBarDoubleClick']);
    // Two slow clicks are not a double-click.
    await clickAt(const Offset(300, 20), 20000);
    await clickAt(const Offset(300, 20), 20900);
    expect(calls, hasLength(1));
  });

  testWidgets(
    'in full screen the sidebar button moves to the edge, where the window buttons hide',
    (tester) async {
      final w = await _world(tester);
      await tester.runAsync(
        () => w.settings.save(w.settings.settings.copyWith(sidebarOpen: false)),
      );
      final vm = SidebarViewModel(
        sessions: w.sessions,
        conversations: w.repo,
        settings: w.settings,
      );
      await tester.pumpWidget(
        AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: ShellScreen(viewModel: vm, selectedId: null, child: const SizedBox()),
        ),
      );
      await tester.pump();
      double left() => tester.getTopLeft(find.bySemanticsLabel('Show sidebar')).dx;
      expect(left(), windowButtonsEnd);
      windowFullScreen.value = true;
      addTearDown(() => windowFullScreen.value = false);
      await tester.pump();
      expect(left(), 16);
      windowFullScreen.value = false;
      await tester.pump();
      expect(left(), windowButtonsEnd);
      vm.dispose();
      w.repo.dispose();
      await tester.runAsync(() => w.root.delete(recursive: true));
    },
  );
}
