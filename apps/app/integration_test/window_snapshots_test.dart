// Run on macOS with Helmy open: fvm flutter test integration_test/window_snapshots_test.dart -d macos
// Snapshots only Helmy's own window (the running app, a process apart from
// this test's), never another app's.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/window_snapshots.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test("Helmy's window is listed and snapshotted, its text read where allowed", () async {
    final dir = await Directory.systemTemp.createTemp('snaps');
    final snaps = WindowSnapshots(appData: () async => dir);
    final access = await snaps.access();
    final windows = await snaps.windows();
    // ignore: avoid_print
    print('access: record=${access.record} read=${access.read}; ${windows.length} windows');
    final helmy = windows.where((w) => w.app == 'Helmy').firstOrNull;
    expect(helmy, isNotNull, reason: 'Helmy is open');
    final shot = await snaps.take(helmy!);
    // ignore: avoid_print
    print(
      'picture: ${shot?.picture != null ? File(shot!.picture).lengthSync() : null} bytes, '
      'text: ${shot?.text == null ? 'none' : File(shot!.text!).readAsLinesSync().length} lines',
    );
    if (shot != null) {
      File(shot.picture).copySync('${Platform.environment['SHOT'] ?? dir.path}/snap.png');
      if (shot.text != null)
        File(shot.text!).copySync('${Platform.environment['SHOT'] ?? dir.path}/snap.md');
    }
    expect(shot, isNotNull);
  });
}
