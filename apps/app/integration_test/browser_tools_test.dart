// Run on macOS: the agent's browser tools on the page in the Preview panel
// (the built-in browser):
// fvm flutter test integration_test/browser_tools_test.dart -d macos
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/browser/browser_host.dart';
import 'package:helmy/data/services/browser/browser_tools.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the agent works the page in the Preview panel the user sees', (tester) async {
    late ChatViewModel vm;
    late String page;
    final host = BrowserHost();
    final tools = BrowserTools(host);
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('panel-tools');
      page = '${root.path}/form.html';
      File(page).writeAsStringSync('''
<html><head><title>Greeter</title></head><body>
<h1>Say hello</h1>
<label for="name">Your name</label> <input id="name">
<button id="go" onclick="document.getElementById('out').textContent = 'Hello, ' + document.getElementById('name').value + '!'">Greet</button>
<p id="out"></p>
</body></html>''');
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
        browser: host,
      );
    });
    // The conversation is on screen with its panel shut: browser_open opens it.
    await tester.pumpWidget(
      AshlarApp(
        theme: appTheme,
        darkTheme: appDarkTheme,
        themeMode: .dark,
        home: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => vm.panel == SidePanel.preview
              ? SizedBox(width: 600, height: 600, child: PreviewPanel(vm: vm))
              : const SizedBox(),
        ),
      ),
    );
    String text(Map r) => ((r['content'] as List).first as Map)['text'] as String;
    Future<Map> call(String name, Map args) async {
      final pending = tools.call(name, args, vm.sessionId);
      Map? out;
      pending.then((r) => out = r);
      for (var i = 0; i < 300 && out == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      return out!;
    }

    final opened = await call('browser_open', {'url': Uri.file(page).toString()});
    expect(opened['isError'], isFalse, reason: text(opened));
    expect(vm.panel, SidePanel.preview, reason: 'the panel opened for it');
    final outline = text(opened);
    final box = RegExp(r'textbox "Your name" \[(e\d+)\]').firstMatch(outline)?.group(1);
    final button = RegExp(r'button "Greet" \[(e\d+)\]').firstMatch(outline)?.group(1);
    expect(box, isNotNull, reason: outline);

    final acted = await call('browser_act', {
      'steps': [
        {'do': 'type', 'ref': box, 'text': 'Tito'},
        {'do': 'click', 'ref': button},
      ],
    });
    expect(acted['isError'], isFalse, reason: text(acted));
    expect(text(acted), contains('Hello, Tito!'));

    final shot = await call('browser_screenshot', {});
    expect(((shot['content'] as List).first as Map)['type'], 'image');
    await tester.pumpWidget(const SizedBox());
  });
}
