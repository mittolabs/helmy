// Run on macOS with a simulator installed:
// fvm flutter test integration_test/device_3d_test.dart -d macos
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/devices.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/device_panel.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';

const shot = String.fromEnvironment('SHOT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Device panel shows the screen in 3D', (tester) async {
    final root = await Directory.systemTemp.createTemp('device');
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
    final created = (await sessions.create(cwd: root.path) as Ok).value as Session;
    final vm = ChatViewModel(
      sessionId: created.id,
      sessions: sessions,
      conversations: repo,
      devices: DeviceService(CliLocator()),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      AshlarApp(
        theme: appTheme,
        darkTheme: appDarkTheme,
        themeMode: .dark,
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              width: 420,
              height: 760,
              color: const Color(0xFF000000),
              child: DevicePanel(vm: vm),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 60 && vm.device?.screen == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.runAsync(() => vm.device!.toggle3D());
    for (var i = 0; i < 40 && vm.device!.layers == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    // Hold the picture still and let it decode.
    vm.device!.pause();
    await tester.pump();
    final context = key.currentContext!;
    await tester.runAsync(() => precacheImage(MemoryImage(vm.device!.screen!), context));
    await tester.pump();
    expect(vm.device!.screen, isNotNull);
    expect(vm.device!.layers, isNotEmpty);
    if (shot.isNotEmpty) {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(shot).writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    if (vm.device!.threeD) await tester.runAsync(() => vm.device!.toggle3D());
    vm.device!.pause();
  });
}
