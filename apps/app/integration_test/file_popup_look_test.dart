// A look at the file popup for each kind of file, on this Mac:
// fvm flutter test integration_test/file_popup_look_test.dart -d macos
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/editors.dart';
import 'package:helmy/data/services/watch_service.dart' show Frame;
import 'package:helmy/ui/chat/widgets/file_popup.dart';
import 'package:helmy/ui/chat/widgets/player.dart';
import 'package:provider/provider.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/file_actions.dart';
import 'package:integration_test/integration_test.dart';

const files = String.fromEnvironment('FILES');
const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('each kind of file in the popup', (tester) async {
    final desktop = DesktopService();
    final found = await tester.runAsync(() => EditorService().installed()) ?? const <Editor>[];
    final all = editorsFor(files, found);
    final EditorChoice choice = (
      all: all,
      usual: defaultEditor(all, null),
      open: (_, _) async => true,
    );
    for (final name in ['plan.html', 'format.dart', 'plan.rtf']) {
      final path = '$files/$name';
      if (!File(path).existsSync()) continue;
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => PoppedOut(),
          child: AshlarApp(
            theme: appTheme,
            darkTheme: appDarkTheme,
            home: Builder(
              builder: (context) => GestureDetector(
                onTap: () => showFilePopup(context, path, _Actions(desktop), editors: choice),
                child: const SizedBox.expand(child: Text('open')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await tester.runAsync(() async {
        final id = (await Process.run('swift', [
          '$shots/../winof.swift',
          'Helmy',
        ])).stdout.toString().trim();
        await Process.run('screencapture', ['-x', '-o', '-l', id, '$shots/$name.png']);
      });
      Navigator.of(tester.element(find.byType(Navigator).first), rootNavigator: true).pop();
      await tester.pumpAndSettle();
    }
  });
}

class _Actions implements MediaActions {
  _Actions(this.d);
  final DesktopService d;
  @override
  void preview(String url) => throw StateError('nothing goes to the Preview panel');
  @override
  Future<void> open(String where) async {}
  @override
  Future<void> reveal(String path) async {}
  @override
  Future<bool> copyImage(String path) async => true;
  @override
  Future<String?> documentPicture(String path) => d.documentPicture(path);
  @override
  Future<String?> documentText(String path) async => d.documentText(path);
  @override
  Future<List<Frame>> frames(String path, {int count = 0, int width = 0}) async => const [];
}
