// Run on macOS: fvm flutter test integration_test/chat_page_test.dart -d macos \
//   --dart-define=SHOT=/path/to/chat.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chats/chat_page_screen.dart';
import 'package:helmy/ui/chats/chat_page_view_model.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';

const shot = String.fromEnvironment('SHOT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("a chat's page", (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final root = await Directory.systemTemp.createTemp('chatpage');
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final chats = ChatRepository(storage, sessions);
    await chats.load();
    Future<Session> t(String title, String cwd) async =>
        (await sessions.create(cwd: cwd, title: title) as Ok).value as Session;
    final a = await t('Scope the first version', '/Users/me/rika');
    final b = await t('Design the onboarding screens', '/Users/me/rika-design');
    final c = await t('Build sign-in with Apple', '/Users/me/rika');
    final chat = sessions.byId(a.id)!.chatId!;
    await chats.move(sessions.byId(b.id)!, chat);
    await chats.move(sessions.byId(c.id)!, chat);
    await chats.rename(chat, 'Rika');
    await chats.setBrief(
      chat,
      'Decided: friends only, no public profiles; sign-in with Apple and Google.\n'
      'Open: how invites expire.',
    );
    final vm = ChatPageViewModel(chatId: chat, chats: chats, sessions: sessions);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          themeMode: .dark,
          home: ChatPageScreen(viewModel: vm),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rika'), findsOneWidget);
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
