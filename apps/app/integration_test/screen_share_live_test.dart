// The Mac's screen through Helmy's own Swift side, in the real app: a frame
// captured, and the mark shown then taken down. No input is posted.
// fvm flutter test integration_test/screen_share_live_test.dart -d macos --dart-define=SHOTS=<dir>
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/remote/screen_source.dart';
import 'package:helmy/utils/image_size.dart';
import 'package:integration_test/integration_test.dart';

const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a frame of this screen, then stopped', (tester) async {
    await tester.runAsync(() async {
      final allowed = await MacScreen.allowed();
      // ignore: avoid_print
      print('allowed: $allowed');
      final screen = MacScreen();
      final frames = <Uint8List>[];
      screen.onFrame = frames.add;
      final wrong = await screen.start(mark: 'A test is viewing this screen');
      // ignore: avoid_print
      print('start: ${wrong ?? 'ok'}');
      if (wrong != null) return;
      for (var i = 0; i < 50 && frames.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final sw = Stopwatch()..start();
      screen.next();
      for (var i = 0; i < 50 && frames.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // ignore: avoid_print
      print('frames: ${frames.length}, next took ${sw.elapsedMilliseconds} ms, '
          'size ${imageSize(frames.first)}, ${frames.first.length ~/ 1024} KB');
      if (shots.isNotEmpty) await File('$shots/frame.jpg').writeAsBytes(frames.first);
      await screen.stop();
      expect(frames, isNotEmpty);
    });
  });
}
