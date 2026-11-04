// Run on macOS: fvm flutter test integration_test/files_panel_test.dart -d macos \
//   --dart-define=SHOT=/path/to/prefix
// Saves <prefix>-wide.png (tree and a file side by side) and <prefix>-narrow.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/files_panel.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';

const shot = String.fromEnvironment('SHOT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Files tab shows this repository and reads its files', (tester) async {
    final project = Directory.current.parent.parent.path;
    final root = await Directory.systemTemp.createTemp('files');
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
    final vm = ChatViewModel(sessionId: created.id, sessions: sessions, conversations: repo);

    final key = GlobalKey();
    var width = 980.0;
    Future<void> show() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: AshlarApp(
            theme: appTheme,
            darkTheme: appDarkTheme,
            themeMode: .dark,
            home: Center(
              child: SizedBox(width: width, height: 640, child: FilesPanel(vm: vm)),
            ),
          ),
        ),
      );
    }

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    Future<void> save(String name) async {
      if (shot.isEmpty) return;
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shot-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await show();
    await settle();
    expect(find.text('Makefile'), findsOneWidget);
    await tester.tap(find.text('Makefile'));
    await settle();
    await tester.tap(find.text('apps/app'));
    await tester.pump();
    expect(find.textContaining('fvm flutter build macos', findRichText: true), findsWidgets);
    await save('wide');

    width = 380;
    await show();
    await settle();
    // Narrow: the file alone, with a way back; then a Markdown file as it reads.
    await tester.tap(find.bySemanticsLabel('Back to the files'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'claude');
    await tester.pump();
    await tester.tap(find.text('CLAUDE.md'));
    await settle();
    await save('narrow');
  });
}
