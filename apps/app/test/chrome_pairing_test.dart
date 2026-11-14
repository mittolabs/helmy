import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/remote/remote_host.dart';
import 'package:helmy/data/services/remote/remote_server.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';
import 'support/storage.dart';

/// Pairing Helmy in Chrome: no camera there, so the Mac's Phone page gives
/// the same code as a link to copy and paste.
void main() {
  testWidgets('the Phone page copies the pairing link for Chrome', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final settings = FakeSettingsRepository(const AppSettings(remoteOn: true));
    final engines = EngineRegistry([]);
    final meter = UsageMeter();
    late RemoteHost host;
    await tester.runAsync(() async {
      final storage = storageAt(await Directory.systemTemp.createTemp('chrome-pair'));
      final sessions = SessionRepositoryLocal(storage);
      final server = RemoteServer(
        sessions: sessions,
        conversations: ConversationRepositoryEngines(
          engines: engines,
          router: HeadroomRouter(meter),
          meter: meter,
          storage: storage,
          sessions: sessions,
        ),
        port: 47931,
      );
      host = RemoteHost(server, settings);
      for (var i = 0; i < 200 && host.pairing?.device == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: meter,
      memory: MemoryRepositoryEngines(engines),
    )..show(SettingsSection.phone);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          ChangeNotifierProvider<RemoteHost>.value(value: host),
          Provider(create: (_) => DesktopService()),
        ],
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: SettingsScreen(viewModel: vm),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.text('Copy the link for Chrome'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Copy the link for Chrome'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(copied, host.pairing!.link);
    expect(find.text('Link copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() async => host.dispose());
  });
}
