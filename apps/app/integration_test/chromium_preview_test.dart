// Run on macOS with a Chromium-based browser installed:
// fvm flutter test integration_test/chromium_preview_test.dart -d macos --dart-define=SHOT=<file.png>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/chromium/chromium_service.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chromium_view.dart';
import 'package:helmy/ui/chat/widgets/preview_panel.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/result.dart';
import 'package:integration_test/integration_test.dart';

const shot = String.fromEnvironment('SHOT');

/// White; a click turns it amber; typing "hi" in the box turns it green.
const page = '''
<html><body style="margin:0;background:#ffffff">
<input id="q" style="position:absolute;left:20px;top:20px;width:200px;height:40px;font:20px sans-serif">
<script>
addEventListener('mousedown', e => { if (e.target.id !== 'q') document.body.style.background = '#f59e0b'; });
q.addEventListener('input', () => { if (q.value === 'hi') document.body.style.background = '#16a34a'; });
</script></body></html>''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a page drawn by an installed Chromium browser answers clicks and typing', (
    tester,
  ) async {
    late ChatViewModel vm;
    late ChromiumService chromium;
    late String file;
    late ChromiumBrowser? browser;
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('chromium-preview');
      file = '${root.path}/page.html';
      File(file).writeAsStringSync(page);
      chromium = ChromiumService(appData: () async => root);
      browser = await chromium.pick(null);
      final storage = StorageService(root: () async => root);
      final settings = SettingsRepositoryLocal(storage);
      await settings.save(settings.settings.copyWith(previewWith: PreviewEngine.chromium));
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
        settings: settings,
        desktop: DesktopService(),
        chromium: chromium,
      );
    });
    expect(browser, isNotNull, reason: 'a Chromium-based browser is installed');
    final key = GlobalKey();
    vm.preview(Uri.file(file).toString());
    await tester.pumpWidget(
      AshlarApp(
        theme: appTheme,
        darkTheme: appDarkTheme,
        themeMode: .dark,
        home: Align(
          alignment: .topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 600, height: 500, child: PreviewPanel(vm: vm)),
          ),
        ),
      ),
    );

    Future<void> wait(bool Function() done, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 10 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    /// The color of the page at a point of the panel, as drawn.
    Future<Color> colorAt(Offset at) async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba), image.width);
      });
      final (data, width) = bytes!;
      final i = ((at.dy.round() * width) + at.dx.round()) * 4;
      return Color.fromARGB(255, data!.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    }

    /// Within what JPEG pictures lose of a color.
    bool near(Color a, Color b) =>
        (a.r - b.r).abs() < .03 && (a.g - b.g).abs() < .03 && (a.b - b.b).abs() < .03;

    Future<void> settleImage() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    // Its pictures arrive and show.
    await wait(() => find.byType(ChromiumView).evaluate().isNotEmpty);
    await wait(
      () => find
          .descendant(of: find.byType(ChromiumView), matching: find.byType(Image))
          .evaluate()
          .isNotEmpty,
    );
    await settleImage();
    final view = tester.getRect(find.byType(ChromiumView));
    final blank = view.topLeft + const Offset(400, 300);
    expect(near(await colorAt(blank), const Color(0xFFFFFFFF)), isTrue, reason: 'the page, white');

    // A click on the page reaches it.
    await tester.tapAt(blank);
    await settleImage();
    expect(
      near(await colorAt(blank), const Color(0xFFF59E0B)),
      isTrue,
      reason: 'the click turned it amber',
    );

    // Typing into its box reaches it.
    await tester.tapAt(view.topLeft + const Offset(60, 40));
    await settleImage();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'h');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
    await settleImage();
    if (shot.isNotEmpty) {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(shot).writeAsBytesSync(png!.buffer.asUint8List());
    }
    expect(
      near(await colorAt(blank), const Color(0xFF16A34A)),
      isTrue,
      reason: 'typing "hi" turned it green',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(chromium.stop);
  });

  testWidgets('marking an element puts a picture and its details in the message', (tester) async {
    late ChatViewModel vm;
    late ChromiumService chromium;
    late String file;
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('chromium-marks');
      file = '${root.path}/page.html';
      File(file).writeAsStringSync(
        '<html><head><title>Shop</title></head><body style="margin:0">'
        '<button id="buy" style="position:absolute;left:100px;top:100px;width:160px;height:60px">Buy now</button>'
        '</body></html>',
      );
      chromium = ChromiumService(appData: () async => root);
      final storage = StorageService(root: () async => root);
      final settings = SettingsRepositoryLocal(storage);
      await settings.save(settings.settings.copyWith(previewWith: PreviewEngine.chromium));
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
        settings: settings,
        desktop: DesktopService(),
        chromium: chromium,
      );
    });
    vm.preview(Uri.file(file).toString());
    await tester.pumpWidget(
      AshlarApp(
        theme: appTheme,
        darkTheme: appDarkTheme,
        themeMode: .dark,
        home: Align(
          alignment: .topLeft,
          child: SizedBox(width: 600, height: 600, child: PreviewPanel(vm: vm)),
        ),
      ),
    );
    Future<void> wait(bool Function() done, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 10 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    await wait(
      () => find
          .descendant(of: find.byType(ChromiumView), matching: find.byType(Image))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.bySemanticsLabel('Mark up the page for the agent'));
    await wait(() => find.text('Element').evaluate().isNotEmpty, seconds: 5);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    // Click the button on the page: a mark, numbered 1, with a note to type.
    final view = tester.getRect(find.byType(ChromiumView));
    await tester.tapAt(view.topLeft + const Offset(180, 130));
    await wait(
      () => find.bySemanticsLabel(RegExp('Note on mark 1')).evaluate().isNotEmpty,
      seconds: 8,
    );
    expect(find.bySemanticsLabel(RegExp('Note on mark 1, button')), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'make it bigger');
    await tester.tap(find.text('Add to message'));
    await wait(() => vm.attachments.length >= 2, seconds: 10);
    expect(vm.attachments.where((p) => p.endsWith('.png')), hasLength(1));
    final md = vm.attachments.firstWhere((p) => p.endsWith('.md'));
    final text = await tester.runAsync(() => File(md).readAsString());
    expect(text, contains('# Marks on Shop'));
    expect(text, contains('Note: make it bigger'));
    expect(text, contains('Selector: `#buy`'));
    expect(text, contains('"Buy now"'));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(chromium.stop);
  });
}
