import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connections_setup.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/onboarding/view_models/onboarding_view_model.dart';
import 'package:helmy/ui/onboarding/widgets/onboarding_screen.dart';

import '../testing/fake_repositories.dart';

/// Setup that installs and signs in nothing real.
class _Pretend extends ConnectionsSetup {
  _Pretend() : super(CliLocator(), DesktopService());
  final states = {
    'claude': SetupState.signedOut,
    'codex': SetupState.missing,
    'ollama': SetupState.signedOut,
  };
  final asked = <String>[];

  @override
  Future<List<ConnectionCheck>> check() async => [
    for (final e in states.entries) (id: e.key, name: e.key, does: 'does things', state: e.value),
  ];

  @override
  Future<bool> signIn(String id, {String? configDir}) async {
    asked.add('sign in $id');
    states[id] = SetupState.ready;
    return true;
  }

  @override
  Future<String?> signedInAs(String kind, String? folder) async =>
      folder == null || folder.endsWith('-work') ? 'sam@example.com' : null;

  @override
  Future<bool> install(String id) async {
    asked.add('install $id');
    states[id] = SetupState.signedOut;
    return true;
  }
}

void main() {
  testWidgets('three steps after the splash: connections, chats, folders, then Helmy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = FakeSettingsRepository();
    final setup = _Pretend();
    final vm = OnboardingViewModel(setup: setup, settings: settings, engines: EngineRegistry([]));
    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => OnboardingScreen(vm: vm),
        ),
      ],
    );
    await tester.pumpWidget(
      AshlarApp.router(routerConfig: router, theme: appTheme, darkTheme: appDarkTheme),
    );
    await tester.pumpAndSettle();

    // Step 1: each connection gets the one press that moves it on.
    expect(find.text('Connect your AI tools'), findsOneWidget);
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
    // Ready now, and on: a switch to leave it out.
    expect(find.bySemanticsLabel(RegExp('^Use ')), findsOneWidget);
    expect(find.text('Skip for now'), findsNothing);
    // Switched off, nothing is in use: on with nothing, or skip.
    await tester.tap(find.bySemanticsLabel(RegExp('^Use ')));
    await tester.pumpAndSettle();
    expect(find.text('Skip for now'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Use ')));
    await tester.pumpAndSettle();
    expect(find.text('Skip for now'), findsNothing);
    expect(
      find.text('Add another claude account'),
      findsOneWidget,
      reason: 'more accounts, more room, once one is ready',
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Step 2: nothing to bring in here, so it goes straight on.
    expect(find.text('Bring in your conversations'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Step 3: where new chats start; earlier steps stay a press away.
    expect(find.text('Where should new chats start?'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(settings.settings.setupDone, isTrue);
    expect(settings.settings.folderMode, FolderMode.fixed);
    expect(settings.settings.fixedFolder, isNotNull);

    // What was set up, said back, then on into Helmy.
    expect(find.text("You're all set"), findsOneWidget);
    expect(find.text('1 AI tool ready'), findsOneWidget);
    expect(find.text('New chats start in Home'), findsOneWidget);
    await tester.tap(find.text('Open Helmy'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('skipping with nothing ready ends the first run all the same', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = FakeSettingsRepository();
    final vm = OnboardingViewModel(
      setup: _Pretend(),
      settings: settings,
      engines: EngineRegistry([]),
    );
    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => OnboardingScreen(vm: vm),
        ),
      ],
    );
    await tester.pumpWidget(
      AshlarApp.router(routerConfig: router, theme: appTheme, darkTheme: appDarkTheme),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(settings.settings.setupDone, isTrue);
    expect(
      settings.settings.folderMode,
      FolderMode.none,
      reason: 'nothing chosen, nothing changed',
    );
    expect(find.text('home'), findsOneWidget);
  });

  test('a found connection can be named, and another account used in its place', () async {
    final settings = FakeSettingsRepository();
    final setup = _Pretend()..states['claude'] = SetupState.ready;
    final vm = OnboardingViewModel(setup: setup, settings: settings, engines: EngineRegistry([]));
    await vm.check();
    final claude = vm.checks!.firstWhere((c) => c.id == 'claude');
    expect(vm.found, contains('claude'), reason: 'ready when first looked: found');
    expect(vm.who['claude'], 'sam@example.com');
    expect(vm.used('claude'), isTrue, reason: 'found, so on to begin with');

    await vm.setName('claude', 'Personal');
    expect(vm.shownName(claude), 'Claude Code (Personal)');

    // A folder nobody is signed in to: refused, nothing changed.
    expect(await vm.useAccountFolder('claude', 'Work', '/Users/sam/.claude-empty'), isNotNull);
    expect(settings.settings.accounts, isEmpty);
    expect(vm.used('claude'), isTrue);

    // A signed-in folder: that account is added, the found one left out.
    expect(await vm.useAccountFolder('claude', 'Work', '/Users/sam/.claude-work'), isNull);
    expect(settings.settings.accounts.single.folder, '/Users/sam/.claude-work');
    expect(settings.settings.accounts.single.name, 'Work');
    expect(vm.used('claude'), isFalse);
  });
}
