// Run on macOS itself, where the player and the web view are real:
// fvm flutter test integration_test -d macos --dart-define=SAMPLES=<folder>
// with sample.mp4, sample.m4a, sample.pdf and sample.rtf in the folder.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/watch_service.dart';
import 'package:helmy/ui/chat/widgets/media.dart';
import 'package:helmy/ui/chat/widgets/floating_player.dart';
import 'package:helmy/ui/chat/widgets/player.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

const samples = String.fromEnvironment('SAMPLES');

/// The corner player, as the app provides it.
final corner = PoppedOut();

Future<void> show(WidgetTester tester, String file) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider(create: (_) => DesktopService()),
        ChangeNotifierProvider.value(value: corner),
      ],
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
  // A frame either way, so the screen shows what was found.
  await tester.pump(const Duration(milliseconds: 50));
}

/// A player button, by its label.
Finder button(String label) =>
    find.byWidgetPredicate((w) => w is Button && w.semanticLabel == label);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a video plays in place: its frame, its length, and it runs', (tester) async {
    await show(tester, 'sample.mp4');
    await until(tester, () => find.byType(VideoPlayer).evaluate().isNotEmpty);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.textContaining('/ 0:03'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Play (Space)'));
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

  testWidgets('the player has what a player needs', (tester) async {
    await show(tester, 'sample.mp4');
    await until(tester, () => find.byType(VideoPlayer).evaluate().isNotEmpty);
    VideoPlayerController c() =>
        (tester.widget(find.byType(VideoPlayer).first) as VideoPlayer).controller;

    // A click on the picture plays; another pauses.
    await tester.tap(find.byType(VideoPlayer).first);
    await until(tester, () => c().value.isPlaying, seconds: 3);
    expect(c().value.isPlaying, isTrue, reason: 'a click on the picture plays');
    await tester.tap(find.byType(VideoPlayer).first);
    await until(tester, () => !c().value.isPlaying, seconds: 3);
    expect(c().value.isPlaying, isFalse);

    // Keys, once it has focus: Space plays, M mutes, → moves on.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await until(tester, () => c().value.isPlaying, seconds: 3);
    expect(c().value.isPlaying, isTrue, reason: 'Space plays');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await until(tester, () => !c().value.isPlaying, seconds: 3);
    final before = c().value.position;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await until(tester, () => c().value.position > before, seconds: 3);
    expect(c().value.position, greaterThan(before), reason: '→ moves on');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await until(tester, () => c().value.volume == 0, seconds: 2);
    expect(c().value.volume, 0, reason: 'M mutes');
    await tester.tap(button('Sound on (M)'));
    await until(tester, () => c().value.volume == 1, seconds: 2);
    expect(c().value.volume, 1, reason: 'unmuting gives the volume back');

    // Speed steps 1x, 1.25x, ...
    await tester.tap(button('Speed 1×'));
    await until(tester, () => c().value.playbackSpeed == 1.25, seconds: 2);
    expect(c().value.playbackSpeed, 1.25);

    // Full screen, and back with Esc, the same video.
    await tester.tap(button('Full screen (F)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(button('Exit full screen (Esc)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    // On a real device the way out animates in real time.
    await until(tester, () => button('Exit full screen (Esc)').evaluate().isEmpty, seconds: 3);
    expect(button('Exit full screen (Esc)'), findsNothing);
    expect(find.byType(VideoPlayer), findsOneWidget);

    // At the end, play starts it again.
    await c().setPlaybackSpeed(2);
    await c().seekTo(c().value.duration - const Duration(milliseconds: 300));
    await c().play();
    await until(tester, () => c().value.isCompleted, seconds: 4);
    expect(button('Play again'), findsOneWidget);
    await tester.tap(button('Play again'));
    await until(tester, () => c().value.isPlaying, seconds: 3);
    expect(c().value.position, lessThan(const Duration(seconds: 2)), reason: 'from the start');
  });

  testWidgets('without extra windows, a video pops out to the corner and comes back', (
    tester,
  ) async {
    FloatingPlayers.enabled = false;
    addTearDown(() => FloatingPlayers.enabled = true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider(create: (_) => DesktopService()),
          ChangeNotifierProvider.value(value: corner),
        ],
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: Stack(
            children: [
              SingleChildScrollView(
                child: Media(
                  where: '$samples/sample.mp4',
                  words: 'sample',
                  cwd: samples,
                  onPreview: (_) {},
                ),
              ),
              const CornerPlayer(),
            ],
          ),
        ),
      ),
    );
    await until(tester, () => find.byType(VideoPlayer).evaluate().isNotEmpty);
    await tester.tap(button('Play (Space)'));
    await tester.tap(button('Keep watching in a small window on top'));
    await until(tester, () => find.text('Playing in the corner.').evaluate().isNotEmpty);
    expect(find.text('Playing in the corner.'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsOneWidget, reason: 'now in the corner');
    expect(corner.controller!.value.isPlaying, isTrue, reason: 'still playing');
    await tester.tap(find.text('Bring it back'));
    await until(tester, () => find.text('Playing in the corner.').evaluate().isEmpty);
    expect(corner.controller, isNull);
    expect(find.byType(VideoPlayer), findsOneWidget, reason: 'back in its place');
  });

  testWidgets('what is said in a video is heard, on this Mac', (tester) async {
    final watch = WatchService(CliLocator());
    final heard = await watch.listen('$samples/speech.mp4', const Duration(seconds: 4));
    // ignore: avoid_print
    print('HEARD: ${heard.text} / ${heard.reason}');
    expect(heard.reason, isNull);
    expect(heard.text!.toLowerCase(), contains('friday'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('hovering over the bar shows the frame there and its time', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider(create: (_) => DesktopService()),
          Provider(create: (_) => WatchService(CliLocator())),
          ChangeNotifierProvider.value(value: corner),
        ],
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: SingleChildScrollView(
            child: Media(
              where: '$samples/sample.mp4',
              words: 'sample',
              cwd: samples,
              onPreview: (_) {},
            ),
          ),
        ),
      ),
    );
    await until(tester, () => find.byType(VideoPlayer).evaluate().isNotEmpty);
    // The strip of small frames is made in the background.
    await tester.pump(const Duration(seconds: 3));
    final bar = find.byWidgetPredicate((w) => w is Bar && w.label == 'Position');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(bar));
    await until(tester, () => find.text('0:01').evaluate().isNotEmpty, seconds: 3);
    expect(find.text('0:01'), findsOneWidget, reason: 'the time at the middle of a 3s video');
    expect(find.byType(Image), findsOneWidget, reason: 'the frame there');
    await mouse.removePointer();
  });
}
