// Runs Helmy's Mac actions for real on this Mac (no changes made but a
// minute of keeping it awake): MAC=1 fvm flutter test test/mac_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/mac/mac_actions.dart';

void main() {
  final on = Platform.environment['MAC'] == '1';
  final mac = MacActions(native: (_) async => null);
  for (final (name, read) in [
    ('battery', mac.battery),
    ('load', mac.load),
    ('energy', mac.energy),
    ('disk', mac.disk),
    ('network', mac.network),
    ('speed test', mac.speedTest),
  ]) {
    test(
      name,
      () async {
        final s = await read();
        // ignore: avoid_print
        print('$name:\n$s\n');
        expect(s, isNotEmpty);
      },
      skip: !on,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test('keeping awake runs caffeinate, and stopping ends it', () async {
    // Helmy's own: started by its full path, unlike one run by hand.
    Future<int> mine() async => RegExp(
      r'^\s*\d+ /usr/bin/caffeinate -di',
      multiLine: true,
    ).allMatches('${(await Process.run('/bin/ps', ['-axo', 'pid,args'])).stdout}').length;
    final before = await mine();
    try {
      expect(await mac.keepAwake(time: const Duration(minutes: 1)), contains('until'));
      expect(await mine(), before + 1);
    } finally {
      await mac.stopAwake();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(await mine(), before);
  }, skip: !on);
}
