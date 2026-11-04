// Run on macOS: fvm flutter test integration_test/project_menu_test.dart -d macos \
//   --dart-define=SHOT=/path/to/prefix
// Saves <prefix>-menu.png (the project menu, open on this repository) and
// <prefix>-run.png (an action run in its terminal).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/editors.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/project_menu.dart';
import 'package:helmy/ui/chat/widgets/terminal_panel.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';

import '../testing/fake_repositories.dart';

const shot = String.fromEnvironment('SHOT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the project menu opens on this repository, and an action runs', (tester) async {
    // This repository: its Makefile has actions.
    final project = Directory.current.parent.parent.path;
    final root = await Directory.systemTemp.createTemp('menu');
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
    final created = (await sessions.create(cwd: project) as Ok).value as Session;
    repo.of(created.id).loaded = true;
    final vm = ChatViewModel(
      sessionId: created.id,
      sessions: sessions,
      conversations: repo,
      settings: FakeSettingsRepository(),
      editors: EditorService(),
    );
    for (var i = 0; i < 50 && vm.editors.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    }
    // ignore: avoid_print
    print('apps: ${[for (final e in vm.editors) '${e.name} (${e.lastUsed})']}; opens in ${vm.editor?.name}');
    // ignore: avoid_print
    print('actions: ${[for (final a in vm.actions) '${a.name}: ${a.command}']}');
    expect(vm.actions, isNotEmpty);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          themeMode: .dark,
          home: ListenableBuilder(
            listenable: vm,
            builder: (context, _) => Column(
              crossAxisAlignment: .stretch,
              children: [
                Padding(
                  padding: const .all(12),
                  child: Row(
                    mainAxisAlignment: .end,
                    spacing: 2,
                    children: [ProjectRunButton(vm: vm), ProjectMenu(vm: vm)],
                  ),
                ),
                Expanded(
                  child: switch (vm.active) {
                    final tab? => TerminalPanel(
                      key: ValueKey(tab.id),
                      cwd: project,
                      command: tab.action?.command,
                      name: tab.action?.name,
                      runs: tab.runs,
                      onExit: (code) => vm.actionEnded(tab, code),
                    ),
                    null => const SizedBox(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> save(String name) async {
      if (shot.isEmpty) return;
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shot-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await tester.tap(find.byType(ProjectMenu));
    await tester.pumpAndSettle();
    expect(find.text('Add an action...'), findsOneWidget);
    await save('menu');

    // The Makefile's help: it prints and ends.
    await tester.tap(find.text('help'));
    await tester.pumpAndSettle();
    final tab = vm.active!;
    for (var i = 0; i < 100 && tab.exitCode == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(tab.exitCode, 0);
    await tester.pumpAndSettle();
    await save('run');
  });
}
