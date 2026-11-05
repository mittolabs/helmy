// The phone's screens at iPhone size, fed by a real Mac-side server over
// the sealed link: home, the drawer, a chat, settings.
// fvm flutter test integration_test/phone_look_test.dart -d macos --dart-define=SHOTS=<dir>
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/remote/remote_crypto.dart';
import 'package:helmy/data/services/remote/remote_link.dart';
import 'package:helmy/data/services/remote/remote_server.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/phone/phone_shell.dart';
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/storage.dart';
import 'support/shot.dart';

const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('home, drawer, a chat, settings', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    final key = Pairing.newKey();
    late RemoteServer server;
    late RemoteLink link;
    late Session budget;
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('phone-look');
      final storage = storageAt(root);
      final sessions = SessionRepositoryLocal(storage);
      final chats = ChatRepository(storage, sessions);
      await chats.load();
      final meter = UsageMeter();
      final repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      for (final title in ['Logo ideas', 'Trip budget', 'Landing page copy']) {
        await sessions.create(cwd: '/Users/sam/work/site', title: title);
      }
      budget =
          (await sessions.create(
                cwd: '/Users/sam/work/site',
                title: 'Fix the signup form',
              ) as Ok).value
              as Session;
      repo.of(budget.id)
        ..loaded = true
        ..items.addAll([
          UserMessage('The signup form says the email is wrong even when it is fine.'),
          AssistantText('a', 'Found it. The check rejects addresses with a plus in them.'),
          ToolCall(
            id: 't1',
            name: 'Read',
            input: {'file_path': '/Users/sam/work/site/lib/signup.dart'},
          )..result = 'ok',
          ToolCall(
            id: 't2',
            name: 'Edit',
            input: {'file_path': '/Users/sam/work/site/lib/signup.dart'},
          )..result = 'ok',
          AssistantText(
            'b',
            'Fixed: `sam+news@example.com` now passes. I also added a test for it.\n\n'
                '- **Before:** a plus failed the check\n- **After:** any valid address passes',
          ),
        ]);
      server = RemoteServer(sessions: sessions, conversations: repo, chats: chats, port: 47925);
      await server.start(key);
      link = RemoteLink(
        Pairing(hosts: const ['127.0.0.1'], port: 47925, key: key, name: "Sam's MacBook"),
      );
      await link.connect();
      for (var i = 0; i < 100 && link.chats.length < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    });
    await tester.pumpWidget(
      shootable(
        AshlarApp(
          theme: themeFor(Brightness.dark),
          darkTheme: themeFor(Brightness.dark),
          home: PhoneShell(link: link, onUnpair: () {}, look: PhoneLook.dark, onLook: (_) {}),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    await settle();
    if (shots.isNotEmpty) await shot(tester, '$shots/phone-home.png');
    await tester.tap(find.bySemanticsLabel('Chats'));
    await settle();
    if (shots.isNotEmpty) await shot(tester, '$shots/phone-drawer.png');
    expect(find.text('Fix the signup form'), findsOneWidget);
    await tester.tap(find.text('Fix the signup form'));
    await settle();
    await settle();
    if (shots.isNotEmpty) await shot(tester, '$shots/phone-chat.png');
    expect(find.textContaining('Found it.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Chats'));
    await settle();
    await tester.tap(find.bySemanticsLabel('Settings'));
    await settle();
    await settle();
    if (shots.isNotEmpty) await shot(tester, '$shots/phone-settings.png');
    await tester.runAsync(() async {
      link.dispose();
      await server.stop();
    });
  });
}
