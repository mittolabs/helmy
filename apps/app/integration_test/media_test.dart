// Run on macOS itself, where the player and the web view are real:
// fvm flutter test integration_test -d macos --dart-define=SAMPLES=<folder>
// with sample.mp4, sample.m4a, sample.pdf and sample.rtf in the folder.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/ui/chat/widgets/media.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

const samples = String.fromEnvironment('SAMPLES');

Future<void> show(WidgetTester tester, String file) async {
  await tester.pumpWidget(
    Provider(
      create: (_) => DesktopService(),
      child: AshlarApp(
        theme: appTheme,
        darkTheme: appDarkTheme,
        home: SingleChildScrollView(
          child: Media(where: '$samples/$file', words: file, cwd: samples, onPreview: (_) {}),
        ),
      ),
    ),
  );
}

/// Pumps until [found] holds, for up to [seconds].
Future<void> until(WidgetTester tester, bool Function() found, {int seconds = 10}) async {
  for (var i = 0; i < seconds * 10 && !found(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a video plays in place: its frame, its length, and it runs', (tester) async {
    await show(tester, 'sample.mp4');
    await until(tester, () => find.byType(VideoPlayer).evaluate().isNotEmpty);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.textContaining('/ 0:03'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Play'));
    await until(tester, () => find.textContaining('0:01 /').evaluate().isNotEmpty, seconds: 4);
    expect(find.textContaining('0:01 /'), findsOneWidget, reason: 'it played');
  });

  testWidgets('a sound gets its controls and its length', (tester) async {
    await show(tester, 'sample.m4a');
    // Two seconds, encoded, is a hair under: the clock rounds down, as players do.
    final length = find.textContaining(RegExp(r'/ 0:0[12]$'));
    await until(tester, () => length.evaluate().isNotEmpty);
    expect(length, findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing, reason: 'no picture for a sound');
  });

  testWidgets('a PDF is read in a web view, in place', (tester) async {
    await show(tester, 'sample.pdf');
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an office document shows Quick Look\'s picture of it', (tester) async {
    await show(tester, 'sample.rtf');
    await until(tester, () => find.byType(Image).evaluate().isNotEmpty);
    expect(find.byType(Image), findsOneWidget);
  });
}
