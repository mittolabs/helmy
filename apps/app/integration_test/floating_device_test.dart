// Run on macOS with a simulator installed:
// fvm flutter test integration_test/floating_device_test.dart -d macos \
//   --dart-define=SHOT=/path/to/prefix
// Saves <prefix>-docked.png, <prefix>-floating.png and <prefix>-moved.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/devices.dart';
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
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';

const shot = String.fromEnvironment('SHOT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the device floats over the conversation and keeps what it had', (tester) async {
    tester.view.physicalSize = const Size(2600, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final root = await Directory.systemTemp.createTemp('float');
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
    final main =
        (await sessions.create(cwd: root.path, title: 'Settings screen') as Ok).value as Session;
    repo.of(main.id)
      ..loaded = true
      ..items.addAll([
        UserMessage('Make the rows on the settings screen a little taller.'),
        AssistantText('a:0', 'Done: each row is 52 points tall now, up from 44.'),
      ]);
    final vm = ChatViewModel(
      sessionId: main.id,
      sessions: sessions,
      conversations: repo,
      devices: DeviceService(CliLocator()),
    );
    vm.show(.files);
    vm.show(.device);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsRepository>.value(value: FakeSettingsRepository()),
            ChangeNotifierProvider<SessionRepository>.value(value: sessions),
            ChangeNotifierProvider<ConversationRepository>.value(value: repo),
          ],
          child: AshlarApp(
            theme: appTheme,
            darkTheme: appDarkTheme,
            themeMode: .dark,
            home: ChatScreen(viewModel: vm),
          ),
        ),
      ),
    );
    Future<void> settle([int n = 10]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    Future<void> save(String name) async {
      vm.device!.pause();
      await tester.pump();
      if (shot.isEmpty) return;
      final context = key.currentContext!;
      await tester.runAsync(() => precacheImage(MemoryImage(vm.device!.screen!), context));
      await tester.pump();
      final boundary = context.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shot-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    for (var i = 0; i < 60 && vm.device?.screen == null; i++) {
      await settle(1);
    }
    expect(vm.device!.screen, isNotNull);
    // A mark made while docked.
    await tester.runAsync(() => vm.device!.startMarking());
    vm.device!.addMark(.08, .355, .84, .05, const Size(1206, 2622));
    await tester.pump();
    await save('docked');

    await tester.tap(find.bySemanticsLabel('Float over the conversation'));
    await settle(3);
    expect(vm.deviceFloating, isTrue);
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Floating device'),
      findsOneWidget,
    );
    expect(vm.device!.marks.length, 1, reason: 'the device moved whole, its mark with it');
    await save('floating');

    // By its bar, from beside the panel to over the conversation's words.
    final from = vm.deviceFloatAt;
    await tester.drag(find.text(vm.device!.device!.name), const Offset(-500, 60));
    await settle(3);
    expect(vm.deviceFloatAt, isNotNull);
    expect(from, isNull, reason: 'it had not moved before');
    await save('moved');

    await tester.tap(find.bySemanticsLabel('Back into the panel'));
    await settle(3);
    expect(vm.panel, SidePanel.device);
    expect(vm.device!.marks.length, 1);
    vm.device!.stopMarking();
    vm.device!.pause();
    await tester.pumpWidget(const SizedBox());
  });
}
