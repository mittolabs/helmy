// Run on macOS, where the web view is WebKit's:
// fvm flutter test integration_test/preview_test.dart -d macos
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/preview_panel.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';

/// Seconds to keep the page open after, for looking at it from outside
/// (Safari's Develop menu).
const hold = int.fromEnvironment('HOLD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the page answers to zoom, appearance, a hard reload, and has developer tools turned on',
    (tester) async {
      late ChatViewModel vm;
      late String page;
      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('preview');
        page = '${root.path}/page.html';
        File(page).writeAsStringSync(
          '<html><body style="font:32px sans-serif">'
          '<style>@media (prefers-color-scheme: dark){body{background:#111;color:#eee}}</style>'
          '<h1>A page</h1></body></html>',
        );
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
        final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
        vm = ChatViewModel(
          sessionId: s.id,
          sessions: sessions,
          conversations: repo,
          desktop: DesktopService(),
        );
      });
      vm.preview(Uri.file(page).toString());
      await tester.pumpWidget(
        AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          themeMode: .dark,
          home: PreviewPanel(vm: vm),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        }
      }

      await settle();
      expect(find.text('A page'), findsNothing, reason: 'drawn by WebKit, not Flutter');
      final results = <String, bool>{};
      for (final (action, args) in [
        ('zoom', <String, Object?>{'zoom': 1.5}),
        ('appearance', <String, Object?>{'appearance': 'dark'}),
        ('hardReload', <String, Object?>{}),
        ('inspect', <String, Object?>{}),
      ]) {
        results[action] = await tester.runAsync(() => vm.webPage(action, args)) ?? false;
        await settle();
        if (action == 'inspect') {
          await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
          await settle();
        }
      }
      final shot = '${Directory.systemTemp.path}/helmy-snapshot-test.png';
      final saved = await tester.runAsync(() => vm.webSnapshot(shot));
      results['picture'] = saved != null && File(shot).lengthSync() > 1000;
      if (hold > 0) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: hold)));
      }
      expect(results, {
        'zoom': true,
        'appearance': true,
        'hardReload': true,
        'inspect': true,
        'picture': true,
      });
    },
  );
}
