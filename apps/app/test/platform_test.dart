import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/identity.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chat_screen.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/ui/shell/widgets/shell_screen.dart';
import 'package:helmy/utils/platform.dart';
import 'package:helmy/utils/result.dart';
import 'package:provider/provider.dart';

import 'support/storage.dart';

/// Words that belong to a Mac alone.
final _macWords = RegExp(
  r'Finder|the Dock|dock icon|this Mac|your Mac|macOS|⌘|⇧|\bPreview\b(?! panel)|QuickTime',
);

void main() {
  test('shortcuts are written for the computer they are on', () {
    expect(Desktop.mac.keys('⌘N'), '⌘N');
    expect(Desktop.windows.keys('⌘N'), 'Ctrl+N');
    expect(Desktop.linux.keys('⇧⌘Enter'), 'Ctrl+Shift+Enter');
    expect(Desktop.windows.keys('⌘1 to ⌘9'), 'Ctrl+1 to Ctrl+9');
    expect(Desktop.windows.keys('⌘[ / ⌘]'), 'Ctrl+[ / Ctrl+]');
    expect(Desktop.windows.keys('Quit (⌘Q) ends them'), 'Quit (Ctrl+Q) ends them');
    expect(Desktop.windows.shortcut(LogicalKeyboardKey.keyN).control, isTrue);
    expect(Desktop.mac.shortcut(LogicalKeyboardKey.keyN).meta, isTrue);
    expect(Desktop.windows.fileManager, 'File Explorer');
    expect(Desktop.linux.thisComputer, 'this computer');
  });

  test('what every connection is told names no one platform', () {
    expect(helmyIdentity, isNot(contains('Mac')));
    expect(helmyIdentity, isNot(contains('Preview')));
    expect(helmyIdentity, isNot(contains('QuickTime')));
  });

  for (final desktop in [Desktop.windows, Desktop.linux]) {
    testWidgets('on ${desktop.name}, no screen speaks a Mac\'s words', (tester) async {
      Desktop.current = desktop;
      addTearDown(() => Desktop.current = Desktop.mac);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Directory root;
      late SessionRepositoryLocal sessions;
      late SettingsRepository settings;
      late ConversationRepositoryEngines repo;
      late Session session;
      final engines = EngineRegistry([]);
      final meter = UsageMeter();
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('platform');
        final dir = root.path;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir,
        );
        final storage = storageAt(root);
        sessions = SessionRepositoryLocal(storage);
        settings = SettingsRepositoryLocal(storage);
        repo = ConversationRepositoryEngines(
          engines: engines,
          router: HeadroomRouter(meter),
          meter: meter,
          storage: storage,
          sessions: sessions,
        );
        session = (await sessions.create(cwd: root.path) as Ok).value as Session;
        await File('${root.path}/dot.png').writeAsBytes(const [0]);
        repo.of(session.id)
          ..loaded = true
          ..items.addAll([
            UserMessage('show me the picture'),
            AssistantText('a', 'Here it is:\n\n![a dot](${root.path}/dot.png)'),
            TurnSummary(ok: true),
          ]);
        await settings.save(settings.settings.copyWith(sidebarOpen: true));
      });
      final sidebar = SidebarViewModel(sessions: sessions, conversations: repo, settings: settings);
      final chat = ChatViewModel(sessionId: session.id, sessions: sessions, conversations: repo);

      Future<String> shown(Widget page) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsRepository>.value(value: settings),
              Provider(create: (_) => DesktopService()),
            ],
            child: AshlarApp(
              theme: appTheme,
              darkTheme: appDarkTheme,
              home: ShellScreen(viewModel: sidebar, selectedId: session.id, child: page),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 300));
        return [
          for (final e in find.byType(RichText).evaluate())
            (e.widget as RichText).text.toPlainText(),
        ].join('\n');
      }

      final texts = <String>[await shown(ChatScreen(viewModel: chat))];
      for (final section in SettingsSection.values) {
        final vm = SettingsViewModel(
          settings: settings,
          engines: engines,
          meter: meter,
          memory: MemoryRepositoryEngines(engines),
        )..section = section;
        texts.add(await shown(SettingsScreen(viewModel: vm)));
      }
      final all = texts.join('\n');
      expect(all, contains('Show in ${desktop.fileManager}'), reason: 'the picture\'s caption');
      expect(all, contains('Ctrl+N'), reason: 'shortcuts in its own keys');
      final mac = _macWords.allMatches(all).map((m) => m[0]).toSet();
      expect(mac, isEmpty, reason: all.split('\n').where(_macWords.hasMatch).join(' | '));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      chat.dispose();
      sidebar.dispose();
      repo.dispose();
      await tester.runAsync(() => deleteFolder(root));
    });
  }
}
