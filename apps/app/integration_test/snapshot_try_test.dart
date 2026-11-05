// Takes a snapshot of another app's window and plays the snapshot sound,
// as Settings' Try it does, on this Mac:
// fvm flutter test integration_test/snapshot_try_test.dart -d macos
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/window_snapshots.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a snapshot of another window, and its sound', (tester) async {
    final snaps = WindowSnapshots(appData: () async => Directory.systemTemp.createTemp('snaps'));
    await tester.runAsync(() async {
      final windows = await snaps.windows();
      final w = windows.where((w) => w.app != 'Helmy').firstOrNull;
      // ignore: avoid_print
      print('windows: ${windows.length}, trying: ${w?.app}');
      expect(w, isNotNull);
      final shot = await snaps.take(w!);
      // ignore: avoid_print
      print('shot: ${shot?.picture}, text: ${shot?.text != null}');
      expect(shot, isNotNull);
      expect(File(shot!.picture).lengthSync(), greaterThan(1000));
      await snaps.sound('Pop');
      File(shot.picture).deleteSync();
      if (shot.text != null) File(shot.text!).deleteSync();
    });
  });
}
