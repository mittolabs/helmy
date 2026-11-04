// Run on macOS: fvm flutter test integration_test/import_list_test.dart -d macos \
//   --dart-define=SHOT=/path/to/import.png
// Reads this Mac's history to list it; brings nothing in.
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
import 'package:helmy/data/services/history_import.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/import/history_import_view_model.dart';
import 'package:helmy/ui/import/import_list.dart';
import 'package:integration_test/integration_test.dart';

const shot = String.fromEnvironment('SHOT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("the import list shows this Mac's folders", (tester) async {
    final root = await Directory.systemTemp.createTemp('import');
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final vm = HistoryImportViewModel(
      import: HistoryImport(),
      sessions: sessions,
      conversations: ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      ),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          themeMode: .dark,
          home: Center(
            child: Container(
              width: 760,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0x33FFFFFF)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ImportList(vm: vm),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30 && vm.projects == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump();
    expect(vm.projects, isNotEmpty);
    if (shot.isNotEmpty) {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(shot).writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
