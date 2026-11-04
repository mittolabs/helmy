// Run on macOS: fvm flutter test integration_test/pull_requests_test.dart -d macos \
//   --dart-define=SHOT=/path/to/prs.png
// Lists real pull requests of three projects on this Mac; changes nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/pull_requests.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/pull_requests/pull_requests_screen.dart';
import 'package:helmy/ui/pull_requests/pull_requests_view_model.dart';
import 'package:integration_test/integration_test.dart';

import '../testing/fake_repositories.dart';

const shot = String.fromEnvironment('SHOT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pull requests across projects', (tester) async {
    tester.view.physicalSize = const Size(2000, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final home = Platform.environment['HOME']!;
    final root = await Directory.systemTemp.createTemp('prs');
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final vm = PullRequestsViewModel(
      prs: PullRequests(CliLocator()),
      sessions: sessions,
      conversations: ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      ),
      settings: FakeSettingsRepository(
        AppSettings(
          projects: {
            for (final f in [
              '$home/Mittolabs/products/helmy',
              '$home/Mittolabs/products/rika',
              '$home/Mittolabs/products/funnier',
            ])
              f: const ProjectSettings(),
          },
        ),
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
          home: PullRequestsScreen(viewModel: vm),
        ),
      ),
    );
    for (var i = 0; i < 200 && (vm.all == null || vm.all!.any((p) => p.checks == null)); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump();
    expect(vm.all, isNotEmpty);
    if (shot.isNotEmpty) {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(shot).writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
