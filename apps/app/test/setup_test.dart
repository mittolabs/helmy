import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connections_setup.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/setup/setup_screen.dart';
import 'package:provider/provider.dart';

/// Setup that installs and signs in nothing real.
class _Pretend extends ConnectionsSetup {
  _Pretend() : super(CliLocator(), DesktopService());
  final states = {
    'claude': SetupState.signedOut,
    'codex': SetupState.missing,
    'ollama': SetupState.ready,
  };
  final asked = <String>[];

  @override
  Future<List<ConnectionCheck>> check() async => [
    for (final e in states.entries) (id: e.key, name: e.key, does: 'does things', state: e.value),
  ];

  @override
  Future<bool> signIn(String id) async {
    asked.add('sign in $id');
    states[id] = SetupState.ready;
    return true;
  }

  @override
  Future<bool> install(String id) async {
    asked.add('install $id');
    states[id] = SetupState.signedOut;
    return true;
  }
}

void main() {
  testWidgets(
    'each connection gets the one press that moves it on, and setup ends when one is ready',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Directory root;
      late SettingsRepository settings;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('setup');
        settings = SettingsRepository(StorageService(root: () async => root));
      });
      final setup = _Pretend()..states['ollama'] = SetupState.signedOut;
      final router = GoRouter(
        initialLocation: '/setup',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
        ],
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            Provider<ConnectionsSetup>.value(value: setup),
          ],
          child: AshlarApp.router(routerConfig: router, theme: appTheme, darkTheme: appDarkTheme),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Install'), findsOneWidget);
      expect(
        find.text('Start'),
        findsOneWidget,
        reason: 'the model here starts, it does not sign in',
      );
      expect(find.text('Skip for now'), findsOneWidget, reason: 'nothing ready yet');

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(setup.asked, ['sign in claude']);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Skip for now'), findsNothing);

      await tester.tap(find.text('Install'));
      await tester.pumpAndSettle();
      expect(setup.asked.last, 'install codex');

      await tester.tap(find.text("Let's go"));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(settings.settings.setupDone, isTrue);
      expect(find.text('home'), findsOneWidget);
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );

  test('on this computer, setup sees where each connection stands (it changes nothing)', () async {
    final checks = await ConnectionsSetup(CliLocator(), DesktopService()).check();
    // ignore: avoid_print
    print([for (final c in checks) '${c.name}: ${c.state.name}'].join(', '));
    expect(checks.map((c) => c.id), ['claude', 'codex', 'ollama']);
  });
}
