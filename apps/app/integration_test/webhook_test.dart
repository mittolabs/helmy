// Run on macOS: fvm flutter test integration_test/held_message_test.dart -d macos \
//   --dart-define=SHOT=/path/to/held.png
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
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/data/services/webhooks.dart';
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

  testWidgets('a thread is given a webhook address, shown with how to send to it', (tester) async {
    tester.view.physicalSize = const Size(2200, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final root = await Directory.systemTemp.createTemp('held');
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
        (await sessions.create(cwd: root.path, title: 'Budget changes') as Ok).value as Session;
    repo.of(main.id)
      ..loaded = true
      ..items.add(UserMessage('When a pull request opens, review it and say what to fix.'));
    final vm = ChatViewModel(sessionId: main.id, sessions: sessions, conversations: repo);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsRepository>.value(value: FakeSettingsRepository()),
            ChangeNotifierProvider<SessionRepository>.value(value: sessions),
            ChangeNotifierProvider<ConversationRepository>.value(value: repo),
            Provider.value(
              value: Webhooks(sessions: sessions, conversations: repo),
            ),
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
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
    }

    await tester.tap(find.bySemanticsLabel('Chat actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webhook...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Give it an address'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    // The address, and in the command to try it.
    expect(find.textContaining('http://localhost:47821/hooks/'), findsNWidgets(2));

    if (shot.isNotEmpty) {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(shot).writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    await tester.pumpWidget(const SizedBox());
  });
}
