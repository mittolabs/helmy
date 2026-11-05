// A chat as one row, its threads inside it under separators:
// fvm flutter test integration_test/chat_threads_test.dart -d macos --dart-define=SHOTS=<folder>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
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
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/ui/shell/widgets/shell_screen.dart';
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const shots = String.fromEnvironment('SHOTS');
const window = Size(1200, 850);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a chat is one row, and its threads read inside it', (tester) async {
    late SessionRepositoryLocal sessions;
    late SettingsRepository settings;
    late ConversationRepositoryEngines repo;
    late ChatRepository chats;
    late Session budget, taxes, current;
    final now = DateTime.now();
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('threads');
      final storage = StorageService(root: () async => root);
      sessions = SessionRepositoryLocal(storage);
      settings = SettingsRepositoryLocal(storage);
      final meter = UsageMeter();
      repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      chats = ChatRepository(storage, sessions);
      await chats.load();
      Future<Session> thread(String title, String cwd, DateTime at, {String? summary}) async {
        final s = (await sessions.create(cwd: cwd) as Ok).value as Session;
        final dated = Session.fromJson({
          ...s.toJson(),
          'title': title,
          'createdAt': at.toIso8601String(),
          'updatedAt': at.add(const Duration(minutes: 20)).toIso8601String(),
          'summary': ?summary,
        });
        await sessions.save(dated);
        return dated;
      }

      await thread(
        'Plan the launch email',
        '/Users/someone/Projects/site',
        now.subtract(const Duration(hours: 30)),
      );
      budget = await thread(
        'Set a food budget',
        '/Users/someone/Documents',
        now.subtract(const Duration(days: 3)),
        summary: 'Settled on \$400 a month for food, groceries and eating out together.',
      );
      taxes = await thread(
        'What do I owe for Q3?',
        '/Users/someone/Documents',
        now.subtract(const Duration(days: 1)),
      );
      current = await thread(
        'Move savings to the high-yield account',
        '/Users/someone/Documents',
        now.subtract(const Duration(minutes: 30)),
      );
      await thread(
        'Fix the flaky upload test',
        '/Users/someone/Projects/app',
        now.subtract(const Duration(hours: 2)),
      );
      // One chat: Finances, three threads.
      final finances = sessions.byId(budget.id)!.chatId!;
      await chats.move(sessions.byId(taxes.id)!, finances);
      await chats.move(sessions.byId(current.id)!, finances);
      await chats.rename(finances, 'Finances');
      await settings.save(settings.settings.copyWith(sidebarOpen: true));
      for (final (s, said, answered) in [
        (
          budget,
          'Help me set a food budget.',
          'Going by the last three months, \$400 a month covers groceries and eating out.',
        ),
        (
          taxes,
          'What do I owe for Q3?',
          'About **\$1,240**, due September 15. I can set a reminder.',
        ),
        (
          current,
          'Move savings to the high-yield account.',
          'Moving \$2,000 leaves a month of spending in checking. Want me to draft the transfer?',
        ),
      ]) {
        repo.of(s.id)
          ..loaded = true
          ..items.addAll([
            UserMessage(said)..sentAt = s.createdAt,
            AssistantText('a', answered),
            TurnSummary(ok: true)..endedAt = s.createdAt.add(const Duration(minutes: 1)),
          ]);
      }
    });
    final sidebar = SidebarViewModel(
      sessions: sessions,
      conversations: repo,
      settings: settings,
      chats: chats,
    );
    final chat = ChatViewModel(
      sessionId: current.id,
      sessions: sessions,
      conversations: repo,
      chats: chats,
    );

    // The list: one row for Finances, not one per thread.
    final finances = sidebar.entriesOf(sidebar.shown).where((e) => e.chat?.title == 'Finances');
    expect(finances, hasLength(1));
    expect(finances.single.threads, hasLength(3));
    expect(sidebar.inOrder, hasLength(3), reason: 'three chats, three rows');

    // Inside it: the two earlier threads, oldest first, folded.
    expect(chat.earlierThreads.map((t) => t.id), [budget.id, taxes.id]);

    final key = GlobalKey();
    Future<void> shoot(String name) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsRepository>.value(value: settings),
            ChangeNotifierProvider.value(value: sidebar),
            Provider(create: (_) => DesktopService()),
          ],
          child: AshlarApp(
            theme: appTheme,
            darkTheme: appDarkTheme,
            themeMode: .dark,
            home: OverflowBox(
              alignment: .topLeft,
              minWidth: window.width,
              maxWidth: window.width,
              minHeight: window.height,
              maxHeight: window.height,
              child: RepaintBoundary(
                key: key,
                child: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: window),
                    child: ShellScreen(
                      viewModel: sidebar,
                      selectedId: current.id,
                      child: ChatScreen(viewModel: chat),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      if (shots.isEmpty) return;
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await shoot('threads-folded');
    expect(find.text('Set a food budget'), findsOneWidget);
    expect(find.textContaining('Settled on \$400'), findsOneWidget, reason: 'its summary, folded');
    expect(find.text('Help me set a food budget.'), findsNothing);
    chat.toggleThread(budget.id);
    await shoot('threads-open');
    expect(find.text('Help me set a food budget.'), findsOneWidget);

    // Settled: two chats out of the way, at the bottom, opened.
    for (final title in ['Plan the launch email', 'Fix the flaky upload test']) {
      final t = sessions.sessions.firstWhere((x) => x.title == title);
      await tester.runAsync(() => sidebar.settleChat(sidebar.chatOf(t)));
    }
    expect(sidebar.settled, hasLength(2));
    expect(sidebar.entriesOf(sidebar.groups.expand((g) => g.sessions).toList()), hasLength(1));
    sidebar.toggleSettled();
    await shoot('settled');
    expect(find.text('Settled'), findsOneWidget);
    expect(find.bySemanticsLabel('Plan the launch email, settled'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    chat.dispose();
    sidebar.dispose();
  });
}
