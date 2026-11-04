// Run on macOS with an iPhone paired (on the cable or the same Wi-Fi):
// fvm flutter test integration_test/real_iphone_test.dart -d macos \
//   --dart-define=SHOT=/path/to/iphone.png
// Lists the real iPhone, chooses it, and shows what can be done with it,
// or why not (a locked phone says so).
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

  testWidgets('a real iPhone is listed, with what can be done on it', (tester) async {
    final root = await Directory.systemTemp.createTemp('iphone');
    final dir = root;
    final storage = StorageService(root: () async => dir);
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
              height: 640,
              color: const Color(0xFF000000),
              child: DevicePanel(vm: vm),
            ),
          ),
        ),
      ),
    );
    Future<void> settle(bool Function() done) async {
      for (var i = 0; i < 150 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
    }

    final d = vm.device!;
    await settle(() => d.devices.isNotEmpty);
    final phone = d.devices.where((x) => x.realIphone).firstOrNull;
    expect(phone, isNotNull, reason: 'an iPhone is paired and in reach');
    expect(d.device?.realIphone, isFalse, reason: 'chosen only when asked for');
    await tester.runAsync(() => d.choose(phone!));
    await settle(() => d.phoneDoing == null);
    await tester.pump();
    // ignore: avoid_print
    print('apps: ${d.apps?.map((a) => a.bundle).toList()}  trouble: ${d.phoneTrouble}');
    expect(d.apps != null || d.phoneTrouble != null, isTrue);
    if (shot.isNotEmpty) {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(shot).writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    d.pause();
  });
}
