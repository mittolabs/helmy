// Run on macOS: fvm flutter test integration_test/diff_view_test.dart -d macos \
//   --dart-define=SHOT=/path/to/prefix
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/chat/widgets/diff_view.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/diffs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';

const shot = String.fromEnvironment('SHOT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a real diff, side by side and in one column, in each color', (tester) async {
    tester.view.physicalSize = const Size(2200, 1700);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // A real change from this repository: the import list's date column.
    final r = await Process.run('git', ['show', 'a45608c', '--', 'apps/app/lib/ui/chat/widgets/screen/empty.dart'],
        workingDirectory: Directory.current.parent.parent.path);
    final text = '${r.stdout}';
    final diff = parseUnified('empty.dart', text.substring(text.indexOf('@@')));
    final settings = FakeSettingsRepository();
    final key = GlobalKey();
    Future<void> show(DiffColors colors, double width) async {
      await settings.save(AppSettings(diffColors: colors));
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<SettingsRepository>.value(
            value: settings,
            child: AshlarApp(
              theme: appTheme,
              darkTheme: appDarkTheme,
              themeMode: .dark,
              home: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: Padding(padding: const EdgeInsets.all(12), child: DiffView(diff: diff, maxRows: 26)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> save(String name) async {
      if (shot.isEmpty) return;
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shot-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await show(.greenRed, 1100);
    await save('wide-green');
    await show(.blueOrange, 1100);
    await save('wide-blue');
    await show(.none, 520);
    await save('narrow-none');
  });
}
